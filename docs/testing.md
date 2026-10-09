# Testing

Linux Workstation Bootstrap includes an automated Bash test suite for validating the bootstrap foundation without modifying the developer workstation.

The test suite covers core runtime behaviour, operating-system detection, command-line parsing, user configuration, command execution, and distribution adapters.

## Running the Test Suite

From the repository root:

```bash
bash tests/run.sh