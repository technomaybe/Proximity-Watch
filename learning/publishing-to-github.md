# Publishing to GitHub

Notes from making Proximity Watch public.

## Private vs. public repos

A private repo returns "404 Not Found" to anyone not signed in as you, even though it exists. That is on purpose: GitHub does not confirm that a private repo exists. To check what the public sees, look it up while signed out:

```bash
curl -s https://api.github.com/repos/technomaybe/Proximity-Watch | grep visibility
```

## Why a LICENSE file matters

Public code with no license is still "all rights reserved." People can read it, but they are not allowed to copy or reuse it without asking. A license file grants that permission up front.

- **MIT:** short and permissive. Anyone can use, change, or sell it, as long as they keep your copyright notice. You are not liable if it breaks something. The common default for small utilities.
- **Apache 2.0:** like MIT, plus an explicit patent grant. Common for larger projects.
- **GPL:** anyone who ships a changed version has to share their source code too. Keeps derivatives open.

GitHub reads the `LICENSE` file at the root of the repo and shows the license name on the repo page.

## Chaining commands with &&

`a && b && c` runs each command only if the one before it succeeded. If `a` fails, `b` and `c` never run. Use it to stop a sequence safely at the first problem. (`;` runs everything regardless.)

## Redacting screenshots

Cropping beats blurring when the private part sits at an edge: the pixels are gone and nothing looks hidden. Blur can sometimes be reversed, and black bars draw the eye. Better still, hide the panel before taking the screenshot (in Xcode, Option-Command-0 closes the Inspector).

## Retina screenshots

A Mac screenshot is saved at the display's real pixel count, which is usually 2x the "points" macOS draws with. So a window that looks 1,400 wide on screen saves at 2,800 pixels. When cropping by coordinates, scale them to the file's real size.
