from search_agent.citations import render_citations


def test_render_citations_deduplicates_urls() -> None:
    documents = [
        {"title": "One", "source_url": "https://example.test/one"},
        {"title": "Duplicate", "source_url": "https://example.test/one"},
        {"title": "Two", "source_url": "https://example.test/two"},
    ]

    assert render_citations(documents) == (
        "- [One](https://example.test/one)\n"
        "- [Two](https://example.test/two)"
    )


def test_render_citations_skips_missing_urls() -> None:
    assert render_citations([{"title": "No URL"}]) == ""

