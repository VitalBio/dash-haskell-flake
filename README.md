# Dash Haskell Flake

This repository is for building [Dash](https://kapeli.com/dash) docsets using Nix [Haskell
Flakes](https://flake.parts/options/haskell-flake).

I tried to use existing Haskell packages to do this (see [Prior Art](#prior-art)) but couldn't since
they are out of date. Rather than trying to upgrade them, I used the Dash-recommended
[Dashing](https://github.com/technosophos/dashing#readme) package to generate docs, and then indexed
them with CSS selectors:

```json
"selectors": {
  "div#package-header": "Package",
  "div#module-header p": "Module",
  "p.src a[id^=t]": "Type",
  "td.src a[id^=v]": "Constructor",
  "p.src a[id^=v]": "Function"
},
```

## Prior Art

* https://github.com/jfeltz/dash-haskell
* https://github.com/philopon/haddocset
