import pytest

from search_agent.tools.search_private_knowledge import search_private_knowledge


class FakeSearchClient:
    def search(self, **kwargs):
        assert kwargs["search_text"] == "private networking"
        assert kwargs["top"] == 3
        return [
            {
                "id": "network-1",
                "title": "Private networking",
                "content": "Public access is disabled.",
                "source_url": "https://example.test/network",
                "@search.score": 1.0,
            }
        ]


def test_search_returns_citation_fields() -> None:
    assert search_private_knowledge(
        "private networking",
        client=FakeSearchClient(),
    ) == [
        {
            "id": "network-1",
            "title": "Private networking",
            "content": "Public access is disabled.",
            "source_url": "https://example.test/network",
            "score": 1.0,
        }
    ]


@pytest.mark.parametrize("question", ["", "   "])
def test_search_rejects_empty_question(question: str) -> None:
    with pytest.raises(ValueError):
        search_private_knowledge(question, client=FakeSearchClient())

