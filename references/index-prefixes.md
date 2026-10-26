# Index-side prefixes

Based on Varshney & Mc, *Index-Time Prefix Injection for Multi-Tenant
Retrieval* (ACL 2026 Industry) and Anthropic's contextual retrieval. The
claim: a short domain-descriptive string prepended to each document or chunk
before indexing pulls its embedding into a tighter, domain-coherent cluster.
Measured effect: +3-8% Hit@5, -49% failed retrievals (contextual retrieval),
deployed across 400+ tenants and 18 languages.

**Important honesty note:** a text prefix is a soft pull, not a hard filter.
It improves ranking; it does not isolate tenants. If you need hard
boundaries, that is vector-DB namespacing (Pinecone namespaces, Weaviate
multi-tenancy), a different feature with a similar name. Use both together
when you need both.

## The prefix shape

```
<domain> <artifact-type>: <entity>
```

- `payments API reference: refund endpoint`
- `auth runbook: session token rotation`
- `billing incident postmortem: 2026-03 duplicate charges`

Domain first, artifact type second, entity last. Three to twelve words. The
prefix describes the document's *place in the corpus*, not a summary of it.
Applied to the chunk text before embedding **and** before building the
lexical (BM25) index; contextual retrieval shows both benefit.

## Tiered discovery

Use the highest tier available:

1. **Model-generated (preferred).** Sample the corpus, a few hundred docs or
   one per cluster, and draft 3 to 5 candidate prefixes per cluster. A human
   reviews and locks the final set. Use prompt caching when generating at
   scale: the corpus slice is stable context.
2. **Expert curation.** When data policy forbids sending samples to a model,
   a domain expert writes the prefix list from category names alone.
3. **Standard library.** When neither is available, start from
   `prefix-library.md` in this directory and rename to fit.

Never ship a prefix set to a production index that no human has read.

## Lint rules

- **Vague prefixes cluster nothing.** `document:`, `file:`, `misc:`,
  `note:`: banned. If the prefix fits any doc in the corpus it fits none.
- **Overspecific prefixes splinter.** A prefix matching five docs in ten
  thousand is a label, not a namespace. Merge up a level.
- **Consistency beats cleverness.** Same domain, same words, same order,
  everywhere. Two phrasings of the same domain split the cluster in half.
- **Neighbor test.** Two docs sharing a prefix should be documents a user
  would expect to retrieve together. If not, the boundary is drawn wrong.
- **One language policy.** Pick document-language or English prefixes and
  hold it across the corpus; mixing creates per-language cluster drift.

## Evaluating

Before rolling out, run the cheap A/B:

1. Embed a 10% sample with and without prefixes.
2. Compare mean intra-cluster cosine (a prefixed cluster should sit tighter)
   and Hit@k on any labeled queries you have.
3. Record both numbers in `.prefixer/metrics.jsonl`.

If cohesion doesn't move, the prefixes are wrong, usually too vague, not
the method.

## When inside a repo

The same shape applies to things agents write that get searched later:

- Doc frontmatter: `domain: payments`, `type: runbook` near the top.
- Decision records, postmortems, runbooks: lead the title with the domain.
- Chunked code indexes: `lang module type: name`
  (`python auth function: rotate_session`).

## Failure modes seen in production (from the paper)

- Prefix drift: contributors invent new phrasings over time. Fix with a
  checked-in prefix list and linting at write time.
- Prefix swallowing the content: prefixes longer than ~15 words start
  dominating short chunks.
- Retrofit cost: prefixes are decided at index time; adding them later means
  re-embedding. Decide before the first bulk index.
