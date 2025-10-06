# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned for Beta (0.2.0)
- Network output targets (TCP/UDP/HTTP)
- Syslog protocol support
- Configuration file loading
- Enhanced metrics and monitoring
- Hot-reload configuration

## [0.1.0-alpha.1] - 2025-10-05

### Added
- **Configuration Management**
  - JSON configuration file loading and saving
  - Environment variable configuration support (`ZLOG_LEVEL`, `ZLOG_FORMAT`, `ZLOG_OUTPUT`, `ZLOG_FILE`)
  - Configuration hot-reload with callback support
  - Advanced configuration validation with helpful error messages
  - Automatic configuration fixing for common errors
- Core logging functionality with 5 log levels (debug, info, warn, error, fatal)
- Multiple output formats: text, JSON, and binary
- Multiple output targets: stdout, stderr, and file
- Structured logging with type-safe fields (string, int, uint, float, boolean)
- Thread-safe logging with mutex protection
- Log level filtering
- Sampling support for high-volume logging
- File rotation with configurable size limits and backup retention
- Async I/O support for non-blocking logging
- Configurable buffering
- Global default logger with convenience functions
- Modular build system with feature flags:
  - `json_format` - JSON output support
  - `async_io` - Async I/O support
  - `file_targets` - File output and rotation
  - `binary_format` - Binary format support
  - `aggregation` - Batching and deduplication
  - `network_targets` - Network output targets
  - `metrics` - Performance metrics
- Comprehensive test suite:
  - Unit tests for core functionality
  - Integration tests for file rotation and async I/O
  - Platform compatibility tests
  - Property-based tests
  - Memory leak detection tests
  - Benchmark suite with comparative analysis
- Complete documentation:
  - API reference
  - Configuration guide
  - Performance guide
  - Migration guide from other logging libraries
  - Practical examples
- Example programs demonstrating all features

### Performance
- Text format: ~50,000+ messages/ms
- Binary format: ~80,000+ messages/ms
- Structured logging: ~25,000+ messages/ms
- Zero-allocation fast paths
- Optimized binary format with varint encoding
- Efficient async queue processing

### Notes
- This is a release candidate and the API may change before 1.0.0
- Requires Zig 0.16.0-dev or later
- All features are optional and can be disabled at compile time
- Cross-platform support: Linux, macOS, Windows

[0.1.0-rc.1]: https://github.com/ghostkellz/zlog/releases/tag/v0.1.0-rc.1
