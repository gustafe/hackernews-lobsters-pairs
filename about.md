</head>
<body>

# What's all this about, then?

This is a little page that scrapes the APIs for Hackernews and
Lobsters, compares URLs for submissions, and prints a match if the
URLs are the same.

I wrote it to follow discussions on both sites more easily.

The numbers at the end of each submission is the score (net number of
upvotes), the number of comments, and the comment/score ratio. The
ratio is only printed if the sum of the score and comments is 10 or
more.

## How it works

A script is run hourly, reading the latest entries from both
sites. Then the page is generated.

## Limitations

It only matches URLs exactly, so if there are extraneous elements in a
submission to one site, it won't show up.

Hackernews has the most content, so that site is treated as "the
source" for comparisons. However, I find the title moderation on
Lobste.rs more consistent, so the title of the submission from that
site is shown for each pair.

While the HN API offers a list of the latest 500 entries, the script
only scan the [`/newest`](https://lobste.rs/newest) page on Lobste.rs,
and if the number of new entries manages to replace the page entirely
between reads, the script might miss entries.

The scores and comments are only updated occasionally as I don't want to overload the API endpoints.
