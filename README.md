# Contribution Art

This repository paints a repeating `HELLO` pattern on the GitHub contribution
calendar for `choijungmua`.

- Every UTC day receives one light-background commit.
- Letter pixels receive 20 commits so they render darker.
- The 3x5 font uses Monday through Friday, leaving weekend margins.
- A scheduled GitHub Actions workflow extends the pattern every day.

The commits are intentionally synthetic contribution art, not development work.

## Preview

Run the following command to preview the current 53-week window:

```bash
./paint.sh preview
```

To fill any missing commits for the visible contribution window:

```bash
./paint.sh backfill
git push origin main
```
