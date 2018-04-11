#!/bin/bash

# first, reduce the deptree
deptree="$(cat "$1")"
while grep -q '\[ *\]' <<< "$deptree"; do
  pkg=$(grep '\[ *\]' <<< "$deptree" | head -n1 | awk '{print $1}')
  echo "consuming pkg: $pkg"
  deptree="$(sed "/^$pkg :/d; s/ /  /g; s/ $pkg / /g; s/  */ /g" <<< "$deptree")"
done
printf "%s" "$deptree" > DEPTREE.reduced
echo "unresolved pkgs: $(wc -l < DEPTREE.reduced)"

read -r -d '' CMD << 'EOF'
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

cycles=nx.simple_cycles(graph)
for cycle in cycles:
    print(cycle)
EOF

echo "crunching cycles... (press CTRL-C to stop)"
# second, find cycles (sample for up to 5 seconds)
python -c "$CMD" DEPTREE.reduced > DEPTREE.cycles
echo "found cycles:    $(wc -l < DEPTREE.cycles)"

echo "collecting stats..."
# third, count occurrences of pkgnames in the cycles
for pkg in $(awk '{print $1}' < DEPTREE.reduced); do
  count=$(grep "'$pkg'" DEPTREE.cycles | wc -l)
  [ $count -gt 0 ] && echo "$pkg: $count"
done | sort -rgk2 > DEPTREE.stats
echo "all done."
