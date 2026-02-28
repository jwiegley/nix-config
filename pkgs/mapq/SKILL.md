---
name: mapq
description: Query Apple Maps for nearby places with driving/walking/transit directions and travel time.
homepage: https://github.com/jwiegley/nix
metadata:
  {
    "openclaw":
      {
        "emoji": "🗺️",
        "os": ["darwin"],
        "requires": { "bins": ["mapq", "corelocationcli"] },
      },
  }
---

# mapq — Apple Maps Query

Query Apple Maps for nearby places and get driving/walking/transit directions with estimated travel time.

## When to Use

✅ **USE this skill when:**

- User asks how far they are from a place ("How far is the nearest Walgreens?")
- User asks for travel time to a destination ("How long to drive to Costco?")
- Finding nearby businesses, restaurants, gas stations, etc.
- Comparing distances to multiple locations of the same type
- Getting walking or transit time estimates

## When NOT to Use

❌ **DON'T use this skill when:**

- User wants to navigate (open Apple Maps instead: `open "maps://?daddr=ADDRESS"`)
- Looking up a specific address without distance/time context
- Weather, traffic conditions, or road closures (use weather skill)
- International routing with complex border crossings

## Workflow

### 1. Get Current Location

**If the user's message contains GPS coordinates** (e.g., `[GPS: 38.57, -121.39]`), extract
the latitude and longitude directly from the message. This happens when the user sends from
a mobile device via an Apple Shortcut that prepends their iPhone GPS location.

**Otherwise**, get the Mac's location:

```bash
LOC=$(corelocationcli --json)
LAT=$(echo "$LOC" | jq -r .latitude)
LON=$(echo "$LOC" | jq -r .longitude)
```

### 2. Query Apple Maps

```bash
# Find nearest Walgreens by car (default)
mapq --lat "$LAT" --lon "$LON" --query "Walgreens"

# Find nearest coffee shops within walking distance
mapq --lat "$LAT" --lon "$LON" --query "coffee" --transport walking

# Find top 5 nearest gas stations
mapq --lat "$LAT" --lon "$LON" --query "gas station" --count 5

# Transit directions
mapq --lat "$LAT" --lon "$LON" --query "airport" --transport transit
```

### 3. Interpret Results

The output is JSON with a `results` array. Each result includes:
- `name` — Business name
- `address` — Full street address
- `route_miles` — Actual driving/walking distance
- `travel_minutes` — Estimated travel time
- `text_summary` — Human-readable summary (e.g., "2.7 mi, 9 min by car")
- `phone` — Phone number if available
- `url` — Website URL if available

### Transport Types

- `automobile` (default) — Driving directions with traffic-aware estimates
- `walking` — Walking directions and time
- `transit` — Public transit directions (availability varies by city)

## Example Conversation

**User**: "How far am I from the nearest Walgreens?"

1. Get location with `corelocationcli --json`
2. Run `mapq --lat LAT --lon LON --query "Walgreens" --count 1`
3. Read `text_summary` from first result
4. Reply: "The nearest Walgreens is at 3400 Arden Way — about 2.7 miles away, roughly 9 minutes by car."

**User**: "What about walking?"

1. Same location, run `mapq --lat LAT --lon LON --query "Walgreens" --count 1 --transport walking`
2. Reply with walking time estimate

## Error Handling

- If `mapq` exits non-zero, check stderr for the error
- Common errors: "No results found" (try a different query), network timeout
- If `corelocationcli` fails, ask the user for their address and geocode it

## Safety Rules

1. **Never share exact GPS coordinates** with the user — use addresses instead
2. **Do not open Maps.app** unless the user explicitly asks for navigation
3. **Round travel times** to the nearest minute for conversational responses
