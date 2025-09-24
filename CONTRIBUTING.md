# Contributing to zlog

Thank you for your interest in contributing to zlog! This document provides guidelines for contributing to the project.

## Getting Started

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/yourusername/zlog.git
   cd zlog
   ```
3. **Create a branch** for your feature or fix:
   ```bash
   git checkout -b feature/your-feature-name
   ```

## Development Setup

### Prerequisites

- Zig 0.16.0-dev or later
- Git for version control

### Building

```bash
# Basic build
zig build

# Full-featured build
zig build -Dfile_targets=true -Dbinary_format=true -Daggregation=true -Dasync_io=true

# Run tests
zig build test

# Run the example
zig build run
```

### Testing

Always run the test suite before submitting changes:

```bash
# Run all tests
zig build test

# Run tests with all features
zig build test -Dfile_targets=true -Dbinary_format=true -Daggregation=true -Dasync_io=true

# Run specific tests
zig build test --test-filter "benchmark"
```

## Code Style

### Zig Conventions

Follow standard Zig conventions:

- Use `snake_case` for variables and functions
- Use `PascalCase` for types and constants
- Use 4 spaces for indentation
- Keep lines under 120 characters
- Add documentation comments for public APIs

### Example:

```zig
/// Configure logger behavior
pub const LoggerConfig = struct {
    level: Level = .info,
    format: Format = .text,

    /// Validate configuration settings
    pub fn validate(self: LoggerConfig) !void {
        if (!self.format.isAvailable()) {
            return error.FormatNotEnabled;
        }
    }
};
```

## Contributing Guidelines

### 1. Feature Requests

- **Open an issue** first to discuss the feature
- Explain the **use case** and **benefits**
- Consider **backwards compatibility**
- Discuss **performance implications**

### 2. Bug Reports

Include in bug reports:

- **Zig version** and platform
- **Build configuration** (which features enabled)
- **Minimal reproduction** case
- **Expected vs actual** behavior
- **Stack trace** if applicable

### 3. Pull Requests

#### Before Submitting

- [ ] Code follows Zig style conventions
- [ ] Tests pass: `zig build test`
- [ ] New features have tests
- [ ] Documentation updated if needed
- [ ] Changes are backwards compatible (or breaking changes documented)
- [ ] Performance impact considered

#### PR Description

- **Describe the change** and motivation
- **Reference any related issues**
- **List any breaking changes**
- **Include test cases** for new functionality

### 4. Documentation

- Update relevant documentation in `docs/`
- Add examples for new features
- Update README.md if needed
- Keep API documentation current

## Development Areas

### High Priority

- **Performance optimizations** - Always welcome
- **Bug fixes** - Critical issues first
- **Test coverage** - Especially edge cases
- **Documentation** - Examples and guides

### Medium Priority

- **New output formats** - With build flag support
- **Additional aggregation features** - Sampling strategies
- **Network targets** - TCP, UDP, HTTP outputs
- **Platform optimizations** - OS-specific features

### Future Enhancements

- **Log parsing utilities** - For binary format
- **Configuration DSL** - Structured config files
- **Metrics and monitoring** - Built-in performance tracking
- **Plugin system** - Extensible formatters and targets

## Code Organization

### Directory Structure

```
src/
├── root.zig           # Main library code
└── main.zig           # Example application

docs/                  # Documentation
├── README.md          # Overview
├── api.md            # API reference
├── configuration.md   # Config guide
├── performance.md     # Performance guide
├── examples.md        # Usage examples
└── migration.md       # Migration guide

build.zig             # Build configuration
build.zig.zon         # Package metadata
```

### Build System

The build system uses compile-time flags for modularity:

```zig
// Enable features conditionally
if (build_options.enable_json) {
    // JSON-specific code
} else {
    // Fallback implementation
}
```

Always ensure new features:
- Have corresponding build flags
- Gracefully degrade when disabled
- Don't break minimal builds

## Performance Considerations

zlog emphasizes high performance:

- **Zero-cost abstractions** - Disabled features compile to nothing
- **Memory efficiency** - Minimize allocations
- **CPU efficiency** - Fast paths for common cases
- **Scalability** - Handle high-throughput scenarios

### Benchmarking

When making performance changes:

1. **Measure before** implementing
2. **Profile the change** during development
3. **Benchmark after** implementation
4. **Compare results** and document improvements

Include benchmark results in PR descriptions.

## Testing

### Test Categories

1. **Unit tests** - Individual functions and components
2. **Integration tests** - Full logging workflows
3. **Performance tests** - Benchmark critical paths
4. **Build tests** - Different feature combinations
5. **Platform tests** - OS-specific functionality

### Writing Tests

```zig
test "feature description" {
    const allocator = std.testing.allocator;

    var logger = try zlog.Logger.init(allocator, .{
        .level = .debug,
        .format = .text,
    });
    defer logger.deinit();

    logger.info("Test message", .{});

    // Verify behavior
    try std.testing.expect(condition);
}
```

## Review Process

1. **Automated checks** run on all PRs
2. **Manual review** by maintainers
3. **Testing** on multiple platforms
4. **Documentation** review if applicable
5. **Performance** review for sensitive changes

### Review Criteria

- **Correctness** - Code works as intended
- **Performance** - No unnecessary slowdowns
- **Style** - Follows project conventions
- **Tests** - Adequate test coverage
- **Documentation** - Clear and accurate

## Community

### Communication

- **GitHub Issues** - Bug reports and feature requests
- **GitHub Discussions** - Design discussions and questions
- **Pull Requests** - Code contributions

### Code of Conduct

We expect all contributors to:

- Be **respectful** and **inclusive**
- Focus on **constructive feedback**
- **Help others** learn and contribute
- Follow the **golden rule**

## Recognition

Contributors are recognized through:

- **Git commit history**
- **Changelog entries** for significant contributions
- **Documentation mentions** for major features

## Questions?

If you have questions about contributing:

1. Check existing **issues and discussions**
2. Look at **recent pull requests** for examples
3. **Open an issue** for guidance
4. **Start small** with documentation or tests

Thank you for contributing to zlog! 🚀