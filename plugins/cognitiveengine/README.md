# Cognitive Engine Plugin

The Cognitive Engine plugin for OpenRocq implements a comprehensive cognitive architecture inspired by OpenCog's AtomSpace and cognitive science principles.

## Features

### Core Hypergraph Data Structures
- **Nodes**: Basic concepts and entities in the cognitive space
- **Links**: Relationships between nodes with typed connections
- **Tensors**: Multi-dimensional data structures for complex relationships

### AtomSpace-inspired CRUD Operations
- Create, Read, Update, Delete operations for all hypergraph elements
- Query operations for finding nodes and links by various criteria
- Scheme export/import for data interchange

### Task Scheduling Module
- Priority-based task scheduling with dependencies
- Concurrent task execution with configurable limits
- Task state management and statistics tracking

### Attention Allocation (ECAN)
- Economic Attention Network implementation
- Short-term, long-term, and very long-term importance tracking
- Attention spreading and decay mechanisms
- Forgetting of low-attention elements

### Reasoning Engine Stubs
- Probabilistic Logic Network (PLN) integration points
- MOSES (Meta-Optimizing Semantic Evolutionary Search) framework
- Truth value management and inference tracking

### Meta-cognition Capabilities
- Self-monitoring of cognitive processes
- Self-evaluation of performance
- Self-reflection on reasoning patterns
- Adaptive strategy selection
- Cognitive load management

## Usage

### Initialization
```coq
CognitiveEngine Init
```

### Adding Concepts
```coq
CognitiveEngine AddConcept "human"
CognitiveEngine AddConcept "mortal"
```

### Adding Relations
```coq
CognitiveEngine AddRelation 1 2 "inheritance"
```

### Querying
```coq
CognitiveEngine Query "human"
CognitiveEngine Status
```

### Attention Management
```coq
CognitiveEngine Attention 1 0.5
CognitiveEngine Focus 5
```

### Meta-cognition
```coq
CognitiveEngine Introspect
```

### Export/Import
```coq
CognitiveEngine Export
```

### Shutdown
```coq
CognitiveEngine Shutdown
```

## Architecture

The cognitive engine consists of several interconnected modules:

1. **Hypergraph Module**: Core data structures for representing knowledge
2. **Task Scheduler**: Manages cognitive tasks and their execution
3. **ECAN**: Economic attention network for resource allocation
4. **Reasoning**: PLN and MOSES integration for inference
5. **Meta-cognition**: Self-monitoring and adaptation capabilities

## Integration with Scheme

The plugin provides full Scheme export/import capabilities, allowing seamless integration with external cognitive systems and data processing pipelines.

## Testing

Comprehensive unit tests are provided covering all major functionality:
- AtomSpace operations
- Task scheduling
- Attention allocation
- Reasoning capabilities
- Meta-cognitive functions

Run tests with:
```bash
dune exec -- test-suite/unit-tests/plugins/cognitiveengine/test_cognitiveengine.exe
```

## Future Enhancements

- Full MOSES genetic programming implementation
- Advanced PLN rule implementations
- Distributed cognitive processing
- Learning and adaptation mechanisms
- Performance optimization and caching
