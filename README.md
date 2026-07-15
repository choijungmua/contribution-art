# Contribution Art

This repository paints a repeating `HELLO` pattern on the GitHub contribution
calendar for `choijungmua`.

- Empty background days receive one light-background commit.
- Letter pixels target at least 50 total contributions.
- The target rises above the user's busiest non-art day, so real commits are
  included instead of distorting the lettering.
- The 3x5 font uses Monday through Friday, leaving weekend margins.
- GitHub Actions checks the full visible window every six hours.
- Each run creates at most 250 commits and remembers recent commits for 72
  hours while GitHub updates the contribution graph.

The commits are intentionally synthetic contribution art, not development work.

## How synchronization works

The script reads the live GitHub contribution calendar and the contributions
already attributed to this repository. Their difference is treated as the
user's real activity. Letter days are topped up to the adaptive dark target,
while a background commit is added only when the day has no contribution.

Using GitHub's displayed total also repairs dates where an earlier large push
was only partially reflected on the profile. Oldest deficits are handled first
in small batches.

## Preview

Run the following command to preview the current 53-week window:

```bash
./paint.sh preview
```

To inspect the next adaptive batch without creating commits:

```bash
./paint.sh plan
```

To create the planned batch locally:

```bash
./paint.sh sync
git push origin main
```

The profile graph can take time to index new commits. User activity cannot be
removed, so a busy real-activity day may still appear darker than a background
pixel until the next adaptive sync raises the letter target.
