DROP TABLE IF EXISTS tempo30_analysis_result;

CREATE TABLE tempo30_analysis_result AS
WITH 
-- 1. Bounding Box of analysis area
analysis_bbox AS (
    SELECT ST_Transform(
        ST_MakeEnvelope(8.7875, 53.0709, 8.8282, 53.0769, 4326), 
        3857
    ) as geom
),

-- 2. All residential, primary, secondary and tertiary roads with speed > 30km/h
relevant_roads AS (
    SELECT 
        p.osm_id, p.highway, p.name,
        ST_Transform(p.way, 25832) as geom -- UTM Zone32N (EPSG:25832) for metric calculations
    FROM planet_osm_line p, analysis_bbox b
    WHERE p.way && b.geom 
      AND p.highway IN ('residential', 'primary', 'secondary', 'tertiary')
      AND p.highway != 'living_street'
      -- Exclude roads that already have maxspeed 30
      AND NOT (
          (p.tags->'maxspeed') IN ('30', 'DE:zone:30')
      )
)

-- 3. Trigger objects (social facilities, zebra crossings, residential buildings)
trigger_objects AS (
    -- A. Social Facilities (Polygons/Points/Zebras - 50m radius)
    -- We union points and polygons here to simplify the subsequent joins
    SELECT 
        ST_Buffer(ST_Transform(p.way, 25832), 50) as geom, 
        'social_facilities' as type
    FROM planet_osm_polygon p, analysis_bbox b
    WHERE p.way && b.geom
      AND (
          p.amenity IN ('school', 'kindergarten', 'childcare', 'nursing_home', 'hospital')
          OR (p.amenity = 'social_facility' AND (p.tags->'social_facility:for') = 'senior') 
          OR p.leisure = 'playground'
      )
    
    UNION ALL
    -- Social Facilities (Points)
    SELECT 
        ST_Buffer(ST_Transform(p.way, 25832), 50) as geom, 
        'social_facilities' as type
    FROM planet_osm_point p, analysis_bbox b
    WHERE p.way && b.geom
      AND (
          p.amenity IN ('school', 'kindergarten', 'childcare', 'nursing_home', 'hospital')
          OR (p.amenity = 'social_facility' AND (p.tags->'social_facility:for') = 'senior') 
          OR p.leisure = 'playground'
      )

    UNION ALL
    -- Zebra Crossings (Points/Lines - 50m radius)
    SELECT 
        ST_Buffer(ST_Transform(p.way, 25832), 50) as geom, 
        'social_facilities' as type
    FROM planet_osm_point p, analysis_bbox b
    WHERE p.way && b.geom
      AND p.highway = 'crossing' 
      AND ((p.tags->'crossing') = 'zebra' OR (p.tags->'crossing_ref') = 'zebra')
    
    UNION ALL
    
    SELECT 
        ST_Buffer(ST_Transform(p.way, 25832), 50) as geom, 
        'social_facilities' as type
    FROM planet_osm_line p, analysis_bbox b
    WHERE p.way && b.geom
      AND p.highway = 'crossing' 
      AND ((p.tags->'crossing') = 'zebra' OR (p.tags->'crossing_ref') = 'zebra')

    UNION ALL

    -- C. Noise Protection (Polygons/Points - 15m radius)
    SELECT 
        ST_Buffer(ST_Transform(p.way, 25832), 15) as geom, 
        'noise_protection' as type
    FROM planet_osm_polygon p, analysis_bbox b
    WHERE p.way && b.geom AND p.building IN ('residential', 'apartments', 'house', 'terrace')

    UNION ALL
    
    SELECT 
        ST_Buffer(ST_Transform(p.way, 25832), 15) as geom, 
        'noise_protection' as type
    FROM planet_osm_point p, analysis_bbox b
    WHERE p.way && b.geom AND p.building IN ('residential', 'apartments', 'house', 'terrace')
),

-- 4. Road segments that intersect with buffered trigger objects 
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

-- 5. Zone expansion (300m guarantee) & residential assignment
raw_zones AS (
    -- Zone expansion: Buffer road segements by 150 m (ensures 300 m minimum length)
    SELECT ST_Buffer(geom, 150) as geom FROM road_segments
    UNION ALL
    -- Residential roads are base zones
    SELECT geom as geom FROM relevant_roads WHERE highway = 'residential'
),

-- 6. Gap filling: Fills gaps smaller than 500m using morphological closing
gap_fill_mask AS (
    -- Dilation (+250m) followed by Erosion (-250m)
    SELECT 
        ST_Buffer(ST_Union(ST_Buffer(geom, 250)), -250) as geom 
    FROM raw_zones
),

-- 7. Potential candidates within the gap fill mask
candidates AS (
    SELECT 
        r.osm_id, r.name, r.highway,
        ST_Intersection(r.geom, m.geom) as geom
    FROM relevant_roads r, gap_fill_mask m
    WHERE ST_Intersects(r.geom, m.geom)
)
-- Result table with justifications
SELECT 
    row_number() over() as id,
    c.osm_id,
    c.name,
    c.highway,
    
    CASE 
        WHEN c.highway = 'residential' THEN 'Noise protection'
        WHEN EXISTS (
            SELECT 1 FROM road_segments s
            WHERE s.type = 'Social facilities' AND s.geom && c.geom 
                  AND ST_DWithin(c.geom, s.geom, 50)
        ) THEN 'Social facilities'
        WHEN EXISTS (
            SELECT 1 FROM road_segments s
            WHERE s.type = 'Noise protection' AND s.geom && c.geom 
                  AND ST_DWithin(c.geom, s.geom, 15)
        ) THEN 'Noise protection'
        ELSE 'Gap filling / Zone expansion'
    END as justification,
    
    ST_Multi(ST_Transform(c.geom, 3857)) as geom
FROM candidates c
WHERE 
    c.highway = 'residential' -- Residential road segments are always included
    -- Only road segments close to a trigger road segment or with the same road name are included --> Avoid parallel roads being included
    OR EXISTS (
        SELECT 1 
        FROM road_segments s
        WHERE s.geom && c.geom
          AND (
                ST_DWithin(c.geom, s.geom, 1)
                OR (c.name IS NOT NULL AND c.name = s.trigger_road_name)
              )
    );

ALTER TABLE tempo30_analysis_result ADD PRIMARY KEY (id);
CREATE INDEX idx_tempo30_res_geom_test ON tempo30_analysis_result USING GIST (geom);
GRANT SELECT ON tempo30_analysis_result TO geoserver_user;