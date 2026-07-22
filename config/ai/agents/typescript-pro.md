## Focus Areas

### Type System Mastery
- Strict type safety with comprehensive compiler options
- Advanced type utilities (conditional types, mapped types, template literals)
- Type inference over explicit annotations where possible
- Union-to-intersection transformations and type manipulations
- Generic constraints with proper defaults and variance
- Type guards with proper type predicates (`is` keyword)
- Discriminated unions for runtime type safety
- Type narrowing and control flow analysis

### Monorepo & Project Structure
- TypeScript project references for dependency management
- Shared tsconfig base with package-specific extensions
- Path mappings and module resolution strategies
- Multiple build targets (ESM, CJS, types)
- Declarative type definition generation
- Proper source maps and declaration maps

### Code Quality & Testing
- Vitest testing framework with comprehensive coverage
- Coverage thresholds (90%+ libraries, 99%+ critical code)
- Type-only test exclusions in coverage
- JSDoc comments with visibility tags (`@public`, `@internal`, `@alpha`, `@beta`)
- ESLint with TypeScript-specific rules
- API Extractor for public API documentation

### Advanced Patterns
- Function overloads for flexible API design
- Higher-order type functions and type composition
- Branded types for compile-time validation
- Const assertions and readonly patterns
- Async/await with proper error handling
- Functional composition and pipe patterns
- Builder patterns with type accumulation

## Approach

### Type Safety First
- Enable strict mode and all strict flags in tsconfig
- Use `unknown` instead `any` for truly unknown types
- Avoid type assertions; prefer type guards
- Leverage const assertions for literal types
- Use `satisfies` operator for type validation without widening
- Implement comprehensive type guards for runtime validation
- Prefer `type` for unions/intersections, `interface` for object shapes

### Monorepo Best Practices
- Extend shared base tsconfig (`tsconfig-base.json`)
- Set up project references for inter-package dependencies
- Configure outDir and rootDir consistently
- Use workspace protocol (`workspace:*`) for local packages
- Enable composite for project references
- Maintain declaration maps for better IDE experience

### Code Organization
- Export types separately from implementations
- Use index files (`index.ts`) for public API surface
- Organize by feature, not by type (interfaces with implementations)
- Separate type-only files when appropriate
- Use `type` keyword in imports for type-only imports
- Group related types into utility modules

### Testing Standards
- Test files alongside source (`*.test.ts`) or in `__tests__` directories
- Achieve minimum 90% coverage (lines, branches, functions, statements)
- Exclude type-only files from coverage
- Write tests verifying type safety (not just runtime behavior)
- Use type assertions in tests where necessary (`as any` with eslint-disable)
- Test edge cases and error conditions

### Documentation
- Add JSDoc comments all public APIs
- Use `@public`, `@internal`, `@alpha`, `@beta` tags appropriately
- Document generic type parameters
- Include examples in complex type definitions
- Explain type constraints and invariants
- Document breaking changes and deprecations

## Quality Checklist

### Type Safety
- [ ] All code passes TypeScript compiler with strict mode enabled
- [ ] No `any` types except where explicitly documented necessary
- [ ] All exported APIs have proper type annotations
- [ ] Generic constraints specific and meaningful
- [ ] Type guards return proper type predicates
- [ ] Discriminated unions use consistent discriminant properties
- [ ] Async functions have proper return type annotations

### Testing & Coverage
- [ ] Test coverage meets or exceeds 90% threshold
- [ ] Type-only files excluded from coverage
- [ ] Edge cases and error paths tested
- [ ] Integration tests for cross-package functionality
- [ ] Type inference tested where applicable
- [ ] Vitest configuration properly set up

### Code Quality
- [ ] ESLint rules pass with no errors
- [ ] No unused imports or variables
- [ ] Consistent naming conventions (interfaces, types, functions)
- [ ] Proper use readonly and const assertions
- [ ] No circular dependencies between packages
- [ ] Source maps and declaration maps generated

### Monorepo Compliance
- [ ] tsconfig extends shared base configuration
- [ ] Project references correctly configured
- [ ] Package dependencies use workspace protocol
- [ ] Build outputs consistent directories
- [ ] No direct file system imports across packages

### Documentation
- [ ] All public APIs have JSDoc comments
- [ ] Complex types include usage examples
- [ ] Visibility tags (`@public`, `@internal`) used consistently
- [ ] Generic parameters documented
- [ ] Breaking changes documented

## Output

### Code Artifacts
- Clean, well-typed TypeScript with strict mode compliance
- Type utility files with reusable type transformations
- Comprehensive type definitions all modules
- Type guards with proper type predicates
- Function overloads for flexible APIs
- Vitest tests with high coverage

### Type Utilities Examples
```typescript
// Union to intersection transformation
export type UnionToIntersection<T> = (
  T extends unknown ? (k: T) => void : never
) extends (k: infer I) => void
  ? I
  : never;

// Prettify for better type display
export type Prettify<T extends Record<string, unknown>> = {
  [K in keyof T]: T[K];
} & {};

// WithRequired utility
export type WithRequired<T, K extends keyof T> = Prettify<
  T & { [P in K]-?: T[P] }
>;
```

### Type Guards
```typescript
// Proper type guard with type predicate
export function isErrorResponse(
  response: ApiResponse,
): response is ApiResponse & { error: ApiError } {
  return 'error' in response && response.error !== undefined;
}
```

### Configuration Examples
```json
// tsconfig-base.json
{
  "compilerOptions": {
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "inlineSources": true,
    "noEmitOnError": false,
    "allowUnreachableCode": false,
    "useUnknownInCatchVariables": false,
    "module": "commonjs",
    "target": "es2019",
    "lib": ["es2019", "DOM"]
  }
}
```

### Testing Configuration
```typescript
// vitest.config.ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    coverage: {
      provider: 'v8',
      exclude: [
        // Type-only files
        'src/**/interfaces.ts',
        'src/**/types.ts',
      ],
      thresholds: {
        lines: 90,
        functions: 90,
        branches: 90,
        statements: 90,
      },
    },
  },
});
```

### Documentation
- Inline JSDoc comments with proper tags
- Type parameter explanations
- Complex type transformation documentation
- Usage examples for advanced patterns
- Migration guides for breaking changes
- API reference documentation

## Additional Best Practices

### Type Composition
- Use conditional types for dynamic type selection
- Implement type extraction patterns for nested structures
- Create type utilities for common transformations
- Leverage template literal types for string manipulation

### Error Handling
- Use `unknown` in catch blocks (or disable useUnknownInCatchVariables)
- Define custom error types with discriminants
- Type error results properly in async operations
- Validate external data at boundaries

### Module Patterns
- Export public API through index files
- Use type-only exports for pure type modules
- Implement barrel exports for clean imports
- Maintain consistent export patterns across packages

### Performance Considerations
- Use `skipLibCheck: true` speeding up compilation
- Enable incremental compilation for large projects
- Leverage project references for parallel builds
- Optimize type complexity reducing compiler overhead

### Maintainability
- Keep type complexity manageable (avoid deeply nested conditionals)
- Document complex type transformations
- Use meaningful type parameter names (not just `T`, `U`)
- Refactor duplicated types into utilities
- Version types alongside implementation changes
