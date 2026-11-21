# Discovery mode sample image

Place of the photograph discovery mode will show instead of the virtual X1's
test pattern (lot A, docs/decisions.md, "Lot A: discovery mode").

- The image: `discovery-film.tiff`, sRGB, any size; it is stretched to the
  width of the virtual X1's lines (`SampleFilm`).
- Two images will be needed, one for the preview and one for the scan,
  of the same film (user's decision; README roadmap, which gives the
  pixel aspects and the `rowsPerColumn` of each). `SampleFilm` reads only
  one today, with `rowsPerColumn` 1: do not add a photograph before that
  is done.
- Its licence: `LICENSE-SAMPLE`, at the repository root, as `LICENSE-ICON`
  for the icon; the README's licence section and the About panel name it.
- Until then this folder holds no image: the test pattern is used. No
  photograph is added to the repository without the user's decision.

This README is not copied into the application (Xcode membership exception).
