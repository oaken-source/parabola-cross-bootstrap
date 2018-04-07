
import sys
import networkx as nx
import itertools

graph = nx.DiGraph()

with open(sys.argv[1]) as deptree:
    for line in deptree:
        line = line.split('#')[0]
        lhs, rhs = line.split(':')
        lhs = lhs.strip()
        rhs = rhs.lstrip(' [').rstrip('] ')
        graph.add_node(lhs)
        for dep in rhs.split():
            if not dep in graph:
                graph.add_node(dep)
            graph.add_edge(lhs, dep)

print("deptree with %d nodes & %d edges" % (graph.number_of_nodes(), graph.number_of_edges()))
print("")

print("cycles:")
cycles=nx.simple_cycles(graph)
for cycle in itertools.islice(cycles, 10):
    print(cycle)
print("")
