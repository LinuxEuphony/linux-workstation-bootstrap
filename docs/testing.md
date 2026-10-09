# Testing

Linux Workstation Bootstrap includes an automated Bash test suite and shell-quality checks for validating the bootstrap foundation without modifying the developer workstation.

Validation covers core runtime behaviour, operating-system detection, command-line parsing, user configuration, command execution, distribution adapters, Bash syntax, static analysis, and formatting.

## Validation Layers

Repository validation consists of four independent layers:

```text
Bash syntax
ShellCheck
shfmt
Automated tests