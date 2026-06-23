// Command prelude runs the deterministic prelude of an execution skill outside
// the agent, then hands the agent a bundle to work from.
//
//	prelude implement <bead-id> [--dry-run] [--repo DIR]
//	prelude cleanup   <bead-id> [--dry-run] [--repo DIR]
package main

import (
	"fmt"
	"os"

	"harness/prelude"
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	var skill prelude.Skill
	switch os.Args[1] {
	case "implement":
		skill = prelude.Implement
	case "cleanup":
		skill = prelude.Cleanup
	default:
		fmt.Fprintf(os.Stderr, "prelude: unknown skill %q\n", os.Args[1])
		usage()
		os.Exit(2)
	}
	if err := prelude.Run(skill, os.Args[2:]); err != nil {
		fmt.Fprintf(os.Stderr, "prelude: %v\n", err)
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage: prelude <implement|cleanup> <bead-id> [--dry-run] [--repo DIR]")
}
