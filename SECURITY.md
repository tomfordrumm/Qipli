# Security policy

## Supported versions

Security fixes are provided for the latest published Qipli release. Older builds
may be replaced by a newer signed release instead of receiving a separate patch.

## Reporting a vulnerability

Use GitHub private vulnerability reporting for this repository. Open the
Security tab, choose "Report a vulnerability", and include:

- the affected Qipli version and macOS version;
- the steps needed to reproduce the problem;
- the security impact you observed;
- a minimal proof of concept when it is safe to share.

Do not open a public issue for an unpatched vulnerability. Do not attach real
clipboard history, passwords, API keys, Apple signing material, or user data.
Use synthetic values in screenshots and test cases.

If private vulnerability reporting is unavailable, contact the repository owner
through the private contact method listed on the GitHub profile. Please do not
send sensitive details through a public discussion.

## Release trust

Official binaries are attached to releases in this repository. A release ZIP
must have a matching SHA-256 file and pass Developer ID signature, Apple
notarization, stapling, and Gatekeeper checks. CI builds from pull requests and
ordinary pushes are unsigned and are not releases.
