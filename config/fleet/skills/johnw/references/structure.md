# Structural Patterns

Post-structure reference for writing in John Wiegley's voice: Org-mode
header format, section headers, post length, and boilerplate to avoid.

## Org-mode header format

Every post begins with a properties drawer and filetags:

```
:PROPERTIES:
:ID:       [UUID]
:SLUG:     slug-name-here
:CREATED:  [YYYY-MM-DD Day]
:END:
#+filetags: :topic:publish:newartisans:posts:
#+title: Title Goes Here
```

## Section headers

Use Org-mode `* Section Name` headers. Headers are descriptive, not clever:

> "* Importing the CVS history"
> "* The basics"
> "* Enter the Free Monad"
> "* Design and Implementation"

NOT: "* Let's Get Started!", "* The Good Stuff", "* Wrapping Up"

## Post length

Varies enormously. Some posts are 4 paragraphs. Some are 300+ lines. Length
serves the content, never the other way around. The meta-post about shorter
posts is itself one paragraph:

> "I think one reason I've been avoiding posting to my blog lately is the time
> commitment of writing something of decent length. To get over this hump, I'm
> going to shift my focus to writing smaller little discoveries of things I
> find during my researches into Haskell and technology. Let's see how that
> goes."

## No boilerplate sections

Never include:
- "Prerequisites" sections
- "Table of Contents"
- "What you'll learn" lists
- "About the Author"
- "Related Posts"
- "TL;DR" summaries
- "Conclusion" sections
