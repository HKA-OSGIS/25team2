# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- Fixed JavaScript syntax error in `frontend/map.html` where `style: style:` (duplicate label) was corrected to `style:` ([eccacd3](https://github.com/HKA-OSGIS/25team2/commit/eccacd3026dea199bd69c850275f02c7447785d6))

### Changed
- Improved GeoServer startup handling to wait for service availability
- Updated map style configuration with proper indentation
- Replaced `planet_osm_roads` with `tempo30_relevant_roads` table for better analysis
- Updated layer names in GeoServer configuration
- Improved spatial index handling - now automatically created by osm2pgsql

### Added
- Instructions for using custom OSM data in README
- Spatial analysis filtering to exclude roads already marked with 30 km/h speed limit
- CORS-bypassing proxy using Express.js for WFS requests

### Documentation
- Clarified installation steps in README
- Added comprehensive Tempo 30 zone logic documentation
- Documented workflow overview and architecture
