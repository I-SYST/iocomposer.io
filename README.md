# IOcomposer Website

Landing page, Stripe redirect pages, and legal documents for [IOcomposer](https://iocomposer.io) — an AI-powered Eclipse-based IDE for embedded firmware development.

## Pages

| Page | URL | Purpose |
|------|-----|---------|
| Landing | [iocomposer.io](https://iocomposer.io) | Marketing page, Stripe portal return |
| Success | [iocomposer.io/success](https://iocomposer.io/success) | Post-payment confirmation |
| Cancel | [iocomposer.io/cancel](https://iocomposer.io/cancel) | Payment cancellation |
| Terms | [iocomposer.io/terms](https://iocomposer.io/terms) | Terms of Service |
| Privacy | [iocomposer.io/privacy](https://iocomposer.io/privacy) | Privacy Policy |
| Legal | [iocomposer.io/legal](https://iocomposer.io/legal) | Legal Notices & Third-Party Acknowledgements |
| Subprocessors | [iocomposer.io/subprocessors](https://iocomposer.io/subprocessors) | Third-party service providers |

## Deployment

This site is hosted on **GitHub Pages** with a custom domain.

### Initial Setup

1. Push this repo to `IOsonata/iocomposer.io`
2. Go to **Settings → Pages**
3. Set Source to `main` branch, root folder
4. Add custom domain `iocomposer.io`
5. Enable "Enforce HTTPS"

### DNS Configuration

Configure these records at your domain registrar:

| Type | Name | Value |
|------|------|-------|
| A | @ | 185.199.108.153 |
| A | @ | 185.199.109.153 |
| A | @ | 185.199.110.153 |
| A | @ | 185.199.111.153 |
| CNAME | www | iosonata.github.io |

DNS propagation may take up to 24 hours.

## Stripe Integration

After deployment, update Supabase Edge Function secrets:

```
CHECKOUT_SUCCESS_URL = https://iocomposer.io/success
CHECKOUT_CANCEL_URL = https://iocomposer.io/cancel
PORTAL_RETURN_URL = https://iocomposer.io
```

Update Supabase Auth settings:

| Setting | Value |
|---------|-------|
| Site URL | `https://iocomposer.io` |
| Redirect URLs | `https://iocomposer.io/**` |

## File Structure

```
iocomposer.io/
├── index.html              # Landing page
├── screenshot.png          # IDE screenshot
├── install_ioc_macos.sh    # macOS install script
├── install_ioc_linux.sh    # Linux install script
├── install_ioc_windows.ps1 # Windows install script
├── success/
│   └── index.html          # Payment success
├── cancel/
│   └── index.html          # Payment cancelled
├── terms/
│   └── index.html          # Terms of Service
├── privacy/
│   └── index.html          # Privacy Policy
├── legal/
│   └── index.html          # Legal Notices & Third-Party
├── subprocessors/
│   └── index.html          # Subprocessor list
├── CNAME                    # Custom domain config
└── README.md                # This file
```

## Tech Stack

- Pure HTML/CSS (no build step)
- Mobile responsive
- Dark theme matching IDE aesthetic

## Legal Notice

The Terms of Service and Privacy Policy are MVP templates. They should be reviewed by qualified legal counsel before production use.

## Related

- [IOsonata Framework](https://iosonata.io)
- [IOsonata GitHub](https://github.com/IOsonata)

---

© 2025 I-SYST Inc.
