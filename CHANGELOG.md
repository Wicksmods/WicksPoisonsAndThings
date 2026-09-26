# Wick's Poisons and Things - Changelog

## Unreleased

- Combo points over the target's nameplate. Off the game's own class
  resource, which only ever sits under your own plate. Toggle in options.
- An energy bar under them. The pips say how close the finisher is; this
  says whether you can pay for it, without looking away to the player
  frame. Nothing compares the reading, so it draws the same whether the
  client hands energy over plainly or withholds it. Toggle in options.
- Two weapon swap keys, for a slow main hand and a dagger off hand. One
  puts the dagger in your main hand and stealths, the other puts the
  slow weapon back and strikes. They read whatever you are wearing, so
  a new weapon needs nothing done to it, and they address the blades by
  item id rather than by name so two swords called the same thing
  cannot pick the wrong one. Bind them under Key Bindings. The swap
  costs you a swing and your coatings travel with the blades, both of
  which are worth knowing before you use them. /wpt swap says what it
  worked out; /wpt swap strike <spell> rides the swap back on something
  other than Sinister Strike.
- The strip carries the swap as two icons on its right end, each the
  weapon that key puts in your main hand, with a fel edge on the one you
  are already holding there. Clicking one does what the key does. A pair
  it cannot read greys out rather than disappearing, so the strip never
  changes shape on you mid-pull.
- The keys read your stance before moving anything. The stealth key is
  a toggle for the weapons as well as the spell: pressed while
  stealthed it drops stealth and puts the slow weapon back, where
  before it put the dagger up again on the way out. It holds off
  entirely in combat, where Stealth will not cast anyway. And the
  strike key leaves your hands alone while you are stealthed, so a
  press from stealth can no longer strip the dagger you were opening
  with.
- And it waits for Stealth's cooldown. A macro cannot ask about one, so
  while Stealth is down the lines that would put the dagger up are left
  out of the macro entirely, rather than swapping your weapons for a
  cast that goes nowhere. Getting back out of stealth still works, since
  a cooldown should not be able to strand you holding the wrong blade.
- The mark on the strip keeps up with a swap made in combat. Reading
  which hand holds what and redrawing the strip sat behind the guard
  that stops a macro being rewritten mid-fight, which applies to
  neither, so the weapons moved on the key and the mark did not follow
  until the fight ended.

## 0.9.0

One version across the suite for the Forever beta. Every addon carried a
number of its own that said nothing about how finished it was, so they are
aligned here and the suite goes to 1.0.0 together at launch.

## 0.1.0 - 2026-09-18 (Forever, beta)

### First cut of the rogue kit on WickCore

- Requires WickCore. Interface 16001.
- Blade watch: what coats each hand, how long it has left and how many
  charges, read through the client's temporary enchantment info.
- Coating keys, one per hand. The macro is rewritten out of combat to use
  the chosen coating and then that weapon slot. Pin one per hand with
  /wpt pin, or let it take the best you carry.
- Compact strip: both blades on one row, click a blade to recoat, hover
  for detail, right-click for the full panel.
- Talents: export, import, save, apply, through Blizzard's own parser.
- Pre-pull checklist: main hand coated, off hand coated, coatings carried,
  Stealth.
- Racials row. Kit panel at /wpt kit. Minimap launcher and a page under
  Options, Wick's Mods.
