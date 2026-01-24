# Video Files

Place demo videos here:

- `IOcomposer_WizardBLEPeriph.mov` - BLE Peripheral wizard demo
- `IOcomposer_WizardBLEPeriph.mp4` - Same video in MP4 format (recommended for browser compatibility)

## Converting MOV to MP4

For better browser support, convert your .mov to .mp4:

```bash
ffmpeg -i IOcomposer_WizardBLEPeriph.mov -c:v libx264 -crf 23 -c:a aac IOcomposer_WizardBLEPeriph.mp4
```
