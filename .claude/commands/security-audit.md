Review the current project for security issues. Check for:

1. Hardcoded secrets, API keys, or tokens in source files
2. .env files that should be gitignored
3. Overly permissive file permissions
4. Dependencies with known vulnerabilities (check package.json / Cargo.toml / requirements.txt)
5. Unsafe shell command construction (injection risks)
6. Missing input validation at system boundaries

Report findings as a prioritized list with file paths and line numbers.
