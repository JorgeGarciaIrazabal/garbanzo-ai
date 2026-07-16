# Knowledge Base (your documents)

Upload documents once; the assistant automatically quotes the relevant parts
when you ask about them (retrieval-augmented generation).

## How do I add a document?
Open the **Knowledge Base** page and press **Upload**. PDFs, text, markdown,
and similar document formats are supported. Documents are chunked and
embedded in the background — large files may take a moment before they're
searchable.

## How does the assistant use my documents?
On every message, the most relevant chunks are retrieved and injected into
the prompt with their source filename. The assistant cites the filename when
it uses them; reply metadata lists the sources.

## How do I turn document retrieval off for a conversation?
Open the conversation settings panel and switch off "Inject relevant
document excerpts into this conversation" — retrieval is skipped for that
conversation only.

## How do I remove a document?
On the Knowledge Base page, use **Delete document**. Its chunks are removed
from retrieval immediately.
