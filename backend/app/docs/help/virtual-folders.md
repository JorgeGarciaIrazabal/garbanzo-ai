# Virtual folders

## What is a virtual folder?
A private folder stored by Garbanzo AI. Upload files from your desktop or Android
device, keep them across chats, and let the assistant work with them. Files remain
available after you close a chat or switch devices. Virtual folders are separate
from a live folder on your desktop and from the knowledge base.

## Where do I see all my files?
Open **Virtual folders** from the Settings pages list or the chat attachment
menu. Create a folder, open it and upload one or several files.
The folder browser lets you edit/delete folders, create text files, preview or
edit files, remove files and download them. Deleting a folder removes its saved
files from every chat; removing a folder from a chat only detaches it.

If an uploaded filename already exists, choose **Replace** to update that file,
**Keep both** to save a separate copy (for example, `report (2).pdf`), or **Cancel**
to skip it. Other files in the selected batch can still upload. Replacement also
works for PDFs and Office documents and keeps the same saved file identity.
If another device or the assistant changes the file while you are choosing,
replacement fails visibly; refresh and upload again before replacing it.

## How do I use a folder in a chat?
Open **Attach photos or files** (the paperclip in the input box) and choose
**Attach saved folder** to select a saved folder on desktop or Android. Attached
folders appear as chips inside the composer; open a chip to browse its files or
detach it. You can also ask **"Use my Research folder in this chat"**. The
assistant can find and attach your saved folder through its virtual_folders tool.
Allow this tool in the conversation's tool settings when using a restricted list.
The same folder can be used in multiple chats.

## How does the assistant know what a folder is about?
Add a **Purpose or context (optional)** description when creating a folder, or
choose **Edit folder** in the folder browser. Describe the project, what the documents contain,
and any background the assistant should know. Descriptions allow up to 2,000
characters and are saved across devices and chats. The assistant receives the
description whenever the folder is attached, without automatically loading every
file. You can also ask **"Update my Research folder's description to say it
contains orchid field trials"**. The assistant can change its name or description
through chat; editing one preserves the other. Clear the description to remove it.

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
per user, and 20 attached folders per chat. Empty files are allowed. Replacing a
file uses only its change in size for storage limits and does not add another file.
Keeping both uses a new file slot and stores the new copy separately.
Invalid paths, unreadable documents and exceeded limits show explicit errors.
