# 3F (.fff) file format notes

- Big-endian TIFF, three IFDs:
  0. full image, RGB 16-bit, uncompressed, single strip (14-bit data ×4)
  1. thumbnail, RGB 8-bit
  2. same thumbnail, RGB 16-bit
- Private tags:
  - 33723 IPTC
  - 34152 (binary)
  - 34377 Photoshop image resources
  - 46277 binary block (film profile name, curves/tables), not yet decoded
  - 46279 software version and scanner serial number
  - 50457 Apple XML plist (4-byte BE length + XML) with all image settings
  - 50458 preview (header: channels, width, height as shorts, then RGB)

Readable with `tifffile` (Python).
