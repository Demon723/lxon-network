# Keyless Cosign Setup for GitHub Actions

## Overview
Uses OIDC tokens from GitHub Actions for keyless signing with cosign.

## Workflow Permissions Required
```yaml
permissions:
  contents: read
  packages: write
  id-token: write  # Required for OIDC token
  attestations: write  # Required for provenance
```

## Cosign Signing (Keyless)
```yaml
- name: Sign with cosign (keyless)
  uses: sigstore/cosign-installer@v3
  with:
    cosign-release: 'v2.2.0'

- name: Sign container image
  env:
    COSIGN_YES: "true"
  run: |
    cosign sign --yes \
      --annotation "version=${{ github.event.release.tag_name }}" \
      --annotation "source=https://github.com/${{ github.repository }}" \
      ghcr.io/${{ github.repository }}/lxon-node:${{ github.event.release.tag_name }}
```

## Cosign Verification Policy
```yaml
- name: Verify signatures
  run: |
    cosign verify --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
      --certificate-identity=https://github.com/${{ github.repository }}/.github/workflows/docker-publish.yml@refs/heads/main \
      ghcr.io/${{ github.repository }}/lxon-node:${{ github.event.release.tag_name }}
```

## Required Certificate Identity Patterns
| Pattern | Description |
|---------|-------------|
| `https://github.com/ORG/REPO/.github/workflows/WORKFLOW.yml@refs/heads/main` | Main branch workflow |
| `https://github.com/ORG/REPO/.github/workflows/WORKFLOW.yml@refs/tags/v*` | Tag workflow |
| `https://github.com/ORG/REPO/.github/workflows/WORKFLOW.yml@refs/pull/*` | PR workflow (not for release) |

## SLSA Provenance Generation
```yaml
- name: Generate SLSA Provenance
  uses: slsa-framework/slsa-github-generator/.github/workflows/generator_generic_slsa3.yml@v1.9.0
  with:
    base64-subjects: "${{ needs.build.outputs.digest }}"
    provenance-name: slsa-provenance.intoto.jsonl
```

## Verification Commands (Manual)
```bash
# Verify image signature
cosign verify \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
  --certificate-identity-regexp="https://github.com/ORG/REPO/.github/workflows/.*" \
  ghcr.io/ORG/REPO/IMAGE:TAG

# View provenance
cosign verify-attestation \
  --type slsaprovenance \
  ghcr.io/ORG/REPO/IMAGE:TAG | jq .

# Download SBOM
cosign download sbom ghcr.io/ORG/REPO/IMAGE:TAG | jq .
```

## Required GitHub Repository Settings
1. **Actions > General > Workflow permissions**: "Read and write permissions"
2. **Actions > General > Allow GitHub Actions to create and approve pull requests**: Enabled
3. **Packages > Package permissions**: "Inherit from repository" or explicit write
3. **Environments**: Create `production` environment with required reviewers

## Cosign Key Management (Alternative: Hardware Keys)
If not using keyless:
```bash
# Generate key pair
cosign generate-key-pair

# Store private key in GitHub Secrets as COSIGN_PRIVATE_KEY
# Store password in GitHub Secrets as COSIGN_PASSWORD

# Sign with key
cosign sign --key env://COSIGN_PRIVATE_KEY \
  --annotation "version=v1.0.0" \
  ghcr.io/org/repo/image:tag
```

## Verification in Deployment
```yaml
# In deployment workflow
- name: Verify image before deploy
  run: |
    cosign verify \
      --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
      --certificate-identity-regexp="https://github.com/ORG/REPO/.github/workflows/docker-publish.yml@refs/tags/v.*" \
      ghcr.io/ORG/REPO/IMAGE:${{ github.event.inputs.version }}
```

## Troubleshooting
| Error | Cause | Fix |
|-------|-------|-----|
| `no matching certificates` | Wrong identity pattern | Check workflow path and ref |
| `invalid OIDC token` | Missing `id-token: write` | Add permission |
| `rekor log entry not found` | Transparency log delay | Wait 1-2 min, retry |
| `fulcio cert expired` | Cert validity 10 min | Sign immediately after build |

## References
- [cosign keyless](https://docs.sigstore.dev/cosign/keyless/)
- [SLSA GitHub Generator](https://github.com/slsa-framework/slsa-github-generator)
- [GitHub OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)