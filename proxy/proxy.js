// proxy.js
const express = require('express');
const fetch = require('node-fetch'); 
const app = express();

const GEOSERVER_BASE_URL = 'http://localhost:8082/geoserver';
const WORKSPACE = 'roads_ws';
const OUTPUT_FORMAT = 'application/json';
const SRS_NAME = 'EPSG:4326';

// ---------------------------
// CORS Middleware
// ---------------------------
app.use((req, res, next) => {
    res.setHeader('Access-Control-Allow-Origin', '*'); // Allow all domains
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    next();
});


app.options(/(.*)/, (req, res) => {
    res.sendStatus(200);
});


// Used for WFS requests
async function fetchWfs(layerName) {
    const url = `${GEOSERVER_BASE_URL}/${WORKSPACE}/ows?` + // <-- HIER IST DIE KORREKTUR
        `service=WFS&version=2.0.0&request=GetFeature&` +
        `typeName=${WORKSPACE}:${layerName}&outputFormat=${OUTPUT_FORMAT}&srsName=${SRS_NAME}`;
    // const url = `${GEOSERVER_BASE_URL}/${WORKSPACE}/wfs?` +
     //   `service=WFS&version=2.0.0&request=GetFeature&` +
       // `typeName=${WORKSPACE}:${layerName}&outputFormat=${OUTPUT_FORMAT}&srsName=${SRS_NAME}`;

    console.log(`Fetching WFS: ${url}`);

    const response = await fetch(url);
    if (!response.ok) {
        throw new Error(`GeoServer error (${response.status}): ${response.statusText}`);
    }
    return response.text();
}

// Forwarding of tempo30_analysis_result feature layer
app.get('/tempo30-wfs', async (req, res) => {
    const layerName = 'tempo30_analysis_result';
    try {
        const data = await fetchWfs(layerName);
        res.setHeader('Content-Type', OUTPUT_FORMAT);
        res.send(data);
    } catch (err) {
        console.error('Error fetching Tempo 30 WFS:', err.message);
        res.status(500).send(`Error fetching Tempo 30 WFS: ${err.message}`);
    }
});

// Forwarding of planet_osm_roads feature layer
app.get('/roads-wfs', async (req, res) => {
    const layerName = 'planet_osm_roads';
    try {
        const data = await fetchWfs(layerName);
        res.setHeader('Content-Type', OUTPUT_FORMAT);
        res.send(data);
    } catch (err) {
        console.error('Error fetching Roads WFS:', err.message);
        res.status(500).send(`Error fetching Roads WFS: ${err.message}`);
    }
});

// Start proxy server
const PORT = 3000;
app.listen(PORT, () => {
    console.log(`Proxy runs at http://localhost:${PORT}/tempo30-wfs & /roads-wfs`);
});
