# Security policy

prefixer is a Markdown skill plus shell scripts, with no build, no
dependencies, no network access. The main attack surface is the scaffold
scripts running `eval` and `find` on paths in a repo you point them at:
only run them on repos you trust.

Report a vulnerability via GitHub → Security → Report a vulnerability.
Do not file public issues for security findings.
