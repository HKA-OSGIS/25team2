DROP TABLE IF EXISTS tempo30_analysis_result;

CREATE TABLE tempo30_analysis_result AS
WITH 

-- 1. All residential, primary, secondary and tertiary roads with speed > 30km/h
relevant_roads AS (
    SELECT 
        p.osm_id, p.highway, p.name,
        ST_Transform(p.way, 25832) as geom -- UTM Zone32N (EPSG:25832) for metric calculations
    FROM planet_osm_line p
    WHERE p.highway IN ('residential', 'primary', 'secondary', 'tertiary')
      AND p.highway != 'living_street'
      -- Exclude roads that already have maxspeed 30
      AND NOT (
          (p.tags->'maxspeed') IN ('30', 'DE:zone:30')
      )
),

-- 2. Trigger objects (social facilities, zebra crossings, residential buildings)
trigger_objects AS (
    -- A. Social Facilities (Polygons/Points/Zebras - 50m radius)
    -- We union points and polygons here to simplify the subsequent joins
    SELECT 
        ST_Buffer(ST_Transform(p.way, 25832), 50) as geom, 
        'social_facilities' as type
    FROM planet_osm_polygon p
    WHERE (
          p.amenity IN ('school', 'kindergarten', 'childcare', 'nursing_home', 'hospital')
          OR (p.amenity = 'social_facility' AND (p.tags->'social_facility:for') = 'senior') 
          OR p.leisure = 'playground'
      )
    
    UNION ALL
    -- Social Facilities (Points)
    SELECT 
        ST_Buffer(ST_Transform(p.way, 25832), 50) as geom, 
        'social_facilities' as type
    FROM planet_osm_point p
    WHERE (
          p.amenity IN ('school', 'kindergarten', 'childcare', 'nursing_home', 'hospital')
          OR (p.amenity = 'social_facility' AND (p.tags->'social_facility:for') = 'senior') 
          OR p.leisure = 'playground'
      )

    UNION ALL
    -- Zebra Crossings (Points/Lines - 50m radius)
    SELECT 
        ST_Buffer(ST_Transform(p.way, 25832), 50) as geom, 
        'social_facilities' as type
    FROM planet_osm_point p
    WHERE p.highway = 'crossing' 
      AND ((p.tags->'crossing') = 'zebra' OR (p.tags->'crossing_ref') = 'zebra')
    
    UNION ALL
    
    SELECT 
        ST_Buffer(ST_Transform(p.way, 25832), 50) as geom, 
        'social_facilities' as type
    FROM planet_osm_line p
    WHERE p.highway = 'crossing' 
      AND ((p.tags->'crossing') = 'zebra' OR (p.tags->'crossing_ref') = 'zebra')

    UNION ALL

    -- C. Noise Protection (Polygons/Points - 15m radius)
    SELECT 
        ST_Buffer(ST_Transform(p.way, 25832), 15) as geom, 
        'noise_protection' as type
    FROM planet_osm_polygon p
    WHERE p.building IN ('residential', 'apartments', 'house', 'terrace')

    UNION ALL
    
    SELECT 
        ST_Buffer(ST_Transform(p.way, 25832), 15) as geom, 
        'noise_protection' as type
    FROM planet_osm_point p
    WHERE p.building IN ('residential', 'apartments', 'house', 'terrace')
),

-- 3. Road segments that intersect with buffered trigger objects 
road_segments AS (
    SELECT 
        r.osm_id,
        r.name as trigger_road_name, -- Save road name to exclude parallel roads later
        t.type,
        ST_Intersection(r.geom, t.geom) as geom
    FROM relevant_roads r
    INNER JOIN trigger_objects t 
      ON ST_Intersects(r.geom, t.geom)
),

-- 4. Zone expansion (300m guarantee) & residential assignment
raw_zones AS (
    -- Zone expansion: Buffer road segements by 150 m (ensures 300 m minimum length)
    SELECT ST_Buffer(geom, 150) as geom FROM road_segments
    UNION ALL
    -- Residential roads are base zones
    SELECT geom as geom FROM relevant_roads WHERE highway = 'residential'
),

-- 5. Gap filling: Fills gaps smaller than 500m using morphological closing
gap_fill_mask AS (
    -- Dilation (+250m) followed by Erosion (-250m)
    SELECT 
        ST_Buffer(ST_Union(ST_Buffer(geom, 250)), -250) as geom 
    FROM raw_zones
),

-- 6. Potential candidates within the gap fill mask
candidates AS (
    SELECT 
        r.osm_id, r.name, r.highway,
        ST_Intersection(r.geom, m.geom) as geom
    FROM relevant_roads r, gap_fill_mask m
    WHERE ST_Intersects(r.geom, m.geom)
),

-- 7a. Seed segments (Name or <= 1 m to Trigger)
seed_segments AS (
    SELECT DISTINCT
        c.osm_id,
        c.name,
        c.highway,
        c.geom
    FROM candidates c
    JOIN road_segments s
      ON s.geom && c.geom -- Initialer räumlicher Index-Filter
     AND (
             ST_DWithin(c.geom, s.geom, 1) -- Oder sehr nah am Trigger-Segment
             OR (c.name IS NOT NULL AND c.name = s.trigger_road_name) -- Oder gleiche Straße
         )
),

-- 7b. around the corner
tempo30_chain AS (
    SELECT DISTINCT
        s.osm_id,
        s.name,
        s.highway,
        s.geom
    FROM seed_segments s

    UNION ALL

    SELECT DISTINCT
        c.osm_id,
        c.name,
        c.highway,
        c.geom
    FROM candidates c
    JOIN tempo30_chain t
      ON c.osm_id <> t.osm_id -- Nicht sich selbst joinen
     AND c.geom && t.geom
     AND ST_DWithin(c.geom, t.geom, 1) -- Verbunden (Abstand kleiner 1 Meter)
),

-- 7c. Endsegmente: eindeutig + Mindestlänge 300 m
final_segments AS (
    SELECT DISTINCT
        osm_id,
        name,
        highway,
        geom
    FROM tempo30_chain
    WHERE ST_Length(geom) >= 300 -- Mindestlänge 300 m in EPSG:25832 (metrisch)
)

-- 8. Result table with category + justification
SELECT 
    row_number() OVER () AS id,
    f.osm_id,
    f.name,
    f.highway,

    -- category
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM road_segments s
            WHERE s.type = 'social_facilities'
              AND s.geom && f.geom 
              AND ST_DWithin(f.geom, s.geom, 50)
        ) THEN 'social' -- Höchste Priorität (direkter Trigger)
        WHEN EXISTS (
            SELECT 1 FROM road_segments s
            WHERE s.type = 'noise_protection'
              AND s.geom && f.geom 
              AND ST_DWithin(f.geom, s.geom, 15)
        ) THEN 'noise' -- Zweithöchste Priorität
        WHEN f.highway = 'residential' 
            THEN 'residential' -- Basis-Kandidat
        ELSE 'gapfill' -- Lückenschluss / Erweiterung
    END AS category,
    
    -- justification
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM road_segments s
            WHERE s.type = 'social_facilities'
              AND s.geom && f.geom 
              AND ST_DWithin(f.geom, s.geom, 50)
        ) THEN 'Social facilities (school, kindergarten, hospital, playground, crossing)'
        WHEN EXISTS (
            SELECT 1 FROM road_segments s
            WHERE s.type = 'noise_protection'
              AND s.geom && f.geom 
              AND ST_DWithin(f.geom, s.geom, 15)
        ) THEN 'Noise protection (residential buildings)'
        WHEN f.highway = 'residential' 
            THEN 'Residential road (automatic candidate)'
        ELSE 'Gap filling / zone extension (< 500 m)'
    END AS justification,
    
    ST_Multi(ST_Transform(f.geom, 3857)) AS geom
FROM final_segments f;

ALTER TABLE tempo30_analysis_result ADD PRIMARY KEY (id);
CREATE INDEX idx_tempo30_res_geom_test ON tempo30_analysis_result USING GIST (geom);
GRANT SELECT ON tempo30_analysis_result TO geoserver_user;
