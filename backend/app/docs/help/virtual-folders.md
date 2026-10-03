# Virtual folders

## What is a virtual folder?
A private folder stored by Garbanzo AI. Upload files from your desktop or Android
device, keep them across chats, and let the assistant work with them. Files remain
available after you close a chat or switch devices. Virtual folders are separate
from a live folder on your desktop and from the knowledge base.

## Where do I see all my files?
Open **Virtual folders** from the Settings pages list or the folder control above
the chat composer. Create a folder, open it and upload one or several files.
The folder browser lets you rename/delete folders, create text files, preview or
edit files, remove files and download them. Deleting a folder removes its saved
files from every chat; removing a folder from a chat only detaches it.

## How do I use a folder in a chat?
Use the chat's virtual-folder control to select an existing folder. Attached
folders appear as chips above the composer; open a chip to browse its files or
detach it. You can also ask **"Use my Research folder in this chat"**. The
assistant can find and attach your saved folder through its virtual_folders tool.
Allow this tool in the conversation's tool settings when using a restricted list.
The same folder can be used in multiple chats.

## Can the assistant create or edit files?
Yes. Ask it to create a summary, update notes, edit code or write a CSV in an
attached virtual folder. It can read supported documents, including PDF and
Office files. It creates/edits UTF-8 text files such as Markdown, source code,
JSON and CSV. PDF/Office files have read-only extracted previews; binary files
can be stored and downloaded but cannot be edited through the text editor.
If another device or chat changes a file, a stale save fails instead of
overwriting the newer version. Refresh and read the latest version before saving.

## How do I download files?
Use a file's Download button, or download the entire folder as a ZIP. Downloads
are available in the browser without sending a chat message. You can also ask
**"Let me download notes.md"** or **"Download this folder"**; the assistant
provides a Download button in chat. Desktop opens Save As; Android opens its
share/save options. Downloads contain the original file bytes.

## What are the limits?
10 MiB per file, 100 MiB and 500 files per folder, 100 folders and 500 MiB total
per user, and 20 attached folders per chat. Empty files are allowed. Uploading
the same path twice reports a conflict; use the editor to change an existing text
file. Invalid paths, unreadable documents and exceeded limits show explicit errors.
