# blkar-helpers

Helper scripts/programs for using rsbx

## Notes on stability

Helpers are maintained and developed on a best effort basis, and are not heavily tested, while the core program blkar itself is heavily tested and is expected to always work.

When in doubt or when you need to be very certain things do work, invoke blkar directly.

## Index

`ecsbxfs.py`

- Uses Python 3 + FUSE to encode files using blkar
- Requires [`fusepy`](https://github.com/fusepy/fusepy) to be installed
- Heavily inspired by [Thanassis Tsiodras's Reed-Solomon FS](https://www.thanassis.space/rsbep.html)

## License

All files are distributed under the MIT license unless otherwise specified.
