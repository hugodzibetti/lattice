---
name: domain-driven-simplicity
description: >
  Guides the agent to prioritize direct, simple, domain-driven implementations
  and avoid speculative design documents, over-engineering, or unnecessary multi-pass architectures.
---

# Domain-Driven Simplicity Skill

This skill contains constraints and guidelines to prevent agents from overcomplicating designs, adding unnecessary compiler/serialization passes, or getting stuck in endless specification phases.

## Core Directives

### 1. Collapsing Multi-Pass Algorithms
When designing parsers, compilers, serializers, or tree-walking systems, **always challenge the number of passes**.
- **The Pre-Instantiation Pattern:** If references between objects are the reason for a separate pass, see if instantiating all blank domain objects first (Pass 1) allows you to resolve all standard values and references in a single property-evaluation sweep (Pass 2).
- **Rule of Thumb:** Never use \(N\) passes when \(N - 1\) passes are possible. Document the purpose of every pass and justify why it cannot be merged.

### 2. Domain-Driven over Spec-Driven
- Avoid writing design documents unless explicitly requested or there is a massive architectural ambiguity.
- Write code that maps directly to the domain concepts (e.g. Roblox instances, properties, references).
- Choose concrete type representations (like raw integers for Enums) over complex abstraction wrappers.

### 3. Simple Heuristics over Complex Optimizations
- Use simple cost-based calculations (like the RLE cost heuristic) in a single O(N) loop instead of importing or writing complex compression frameworks.
- Prioritize code that is easy to debug, check, and maintain.

## Verification Checklist before Planning
Before submitting an implementation plan:
1. Did I double check the execution passes? Can they be collapsed?
2. Did I choose the simplest representation of types?
3. Am I avoiding unnecessary spec-writing?
