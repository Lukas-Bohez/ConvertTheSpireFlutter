package com.torrentspire.ai

import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.os.Build
import android.os.CancellationSignal
import android.os.Environment
import android.os.ParcelFileDescriptor
import android.os.storage.StorageManager
import android.provider.DocumentsContract
import android.provider.DocumentsProvider
import java.io.File
import java.io.FileNotFoundException

class StorageDocumentsProvider : DocumentsProvider() {
    companion object {
        const val AUTHORITY = "com.torrentspire.ai.documents"

        private val ROOT_PROJECTION = arrayOf(
            DocumentsContract.Root.COLUMN_ROOT_ID,
            DocumentsContract.Root.COLUMN_DOCUMENT_ID,
            DocumentsContract.Root.COLUMN_ICON,
            DocumentsContract.Root.COLUMN_TITLE,
            DocumentsContract.Root.COLUMN_SUMMARY,
            DocumentsContract.Root.COLUMN_FLAGS,
            DocumentsContract.Root.COLUMN_MIME_TYPES,
            DocumentsContract.Root.COLUMN_AVAILABLE_BYTES,
        )

        private val DOCUMENT_PROJECTION = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            DocumentsContract.Document.COLUMN_FLAGS,
            DocumentsContract.Document.COLUMN_SIZE,
        )
    }

    override fun onCreate(): Boolean = true

    override fun queryRoots(projection: Array<String>?): Cursor {
        val result = MatrixCursor(projection ?: ROOT_PROJECTION)
        val storageManager = context!!.getSystemService(Context.STORAGE_SERVICE) as StorageManager

        val roots = mutableListOf<File>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            roots.addAll(
                storageManager.storageVolumes
                    .mapNotNull { it.directory }
                    .filter { it.exists() }
            )
        } else {
            storageManager.storageVolumes.forEach { volume ->
                val path = try {
                    volume.javaClass.getMethod("getPath").invoke(volume) as? String
                } catch (_: Exception) {
                    null
                }
                if (!path.isNullOrBlank()) {
                    val file = File(path)
                    if (file.exists()) {
                        roots.add(file)
                    }
                }
            }
        }

        val deduped = LinkedHashSet<String>()
        for (root in roots) {
            val canonical = try {
                root.canonicalPath
            } catch (_: Exception) {
                root.absolutePath
            }
            if (!deduped.add(canonical)) continue

            result.newRow().apply {
                add(DocumentsContract.Root.COLUMN_ROOT_ID, canonical)
                add(DocumentsContract.Root.COLUMN_DOCUMENT_ID, canonical)
                add(DocumentsContract.Root.COLUMN_TITLE, root.name.ifBlank { "Storage" })
                add(DocumentsContract.Root.COLUMN_SUMMARY, canonical)
                add(DocumentsContract.Root.COLUMN_MIME_TYPES, "*/*")
                add(
                    DocumentsContract.Root.COLUMN_FLAGS,
                    DocumentsContract.Root.FLAG_LOCAL_ONLY or
                        DocumentsContract.Root.FLAG_SUPPORTS_CREATE or
                        DocumentsContract.Root.FLAG_SUPPORTS_IS_CHILD
                )
                add(DocumentsContract.Root.COLUMN_ICON, R.mipmap.ic_launcher)
                add(DocumentsContract.Root.COLUMN_AVAILABLE_BYTES, root.freeSpace)
            }
        }

        return result
    }

    override fun queryDocument(documentId: String, projection: Array<String>?): Cursor {
        val result = MatrixCursor(projection ?: DOCUMENT_PROJECTION)
        includeFile(result, File(documentId))
        return result
    }

    override fun queryChildDocuments(
        parentDocumentId: String,
        projection: Array<String>?,
        sortOrder: String?,
    ): Cursor {
        val result = MatrixCursor(projection ?: DOCUMENT_PROJECTION)
        val parent = File(parentDocumentId)
        parent.listFiles()?.sortedWith(compareBy<File> { !it.isDirectory }.thenBy { it.name.lowercase() })
            ?.forEach { includeFile(result, it) }
        return result
    }

    override fun openDocument(documentId: String, mode: String, signal: CancellationSignal?): ParcelFileDescriptor {
        val file = File(documentId)
        if (file.isDirectory) {
            throw FileNotFoundException("Cannot open directory: $documentId")
        }
        val accessMode = ParcelFileDescriptor.parseMode(mode)
        return ParcelFileDescriptor.open(file, accessMode)
    }

    override fun isChildDocument(parentDocumentId: String, documentId: String): Boolean {
        val parent = File(parentDocumentId)
        val child = File(documentId)
        return try {
            child.canonicalPath.startsWith(parent.canonicalPath)
        } catch (_: Exception) {
            child.absolutePath.startsWith(parent.absolutePath)
        }
    }

    override fun createDocument(parentDocumentId: String, mimeType: String, displayName: String): String {
        val parent = File(parentDocumentId)
        val child = File(parent, displayName)
        if (mimeType == DocumentsContract.Document.MIME_TYPE_DIR) {
            child.mkdirs()
        } else {
            child.parentFile?.mkdirs()
            child.createNewFile()
        }
        return child.absolutePath
    }

    override fun deleteDocument(documentId: String) {
        deleteRecursively(File(documentId))
    }

    override fun renameDocument(documentId: String, displayName: String): String {
        val source = File(documentId)
        val target = File(source.parentFile, displayName)
        if (source.renameTo(target)) {
            return target.absolutePath
        }
        throw FileNotFoundException("Unable to rename $documentId")
    }

    private fun includeFile(result: MatrixCursor, file: File) {
        val mimeType = if (file.isDirectory) {
            DocumentsContract.Document.MIME_TYPE_DIR
        } else {
            "*/*"
        }
        val flags = if (file.isDirectory) {
            DocumentsContract.Document.FLAG_DIR_SUPPORTS_CREATE or
                DocumentsContract.Document.FLAG_SUPPORTS_DELETE or
                DocumentsContract.Document.FLAG_SUPPORTS_RENAME
        } else {
            DocumentsContract.Document.FLAG_SUPPORTS_WRITE or
                DocumentsContract.Document.FLAG_SUPPORTS_DELETE or
                DocumentsContract.Document.FLAG_SUPPORTS_RENAME
        }

        result.newRow().apply {
            add(DocumentsContract.Document.COLUMN_DOCUMENT_ID, file.absolutePath)
            add(DocumentsContract.Document.COLUMN_MIME_TYPE, mimeType)
            add(DocumentsContract.Document.COLUMN_DISPLAY_NAME, file.name.ifBlank { file.absolutePath })
            add(DocumentsContract.Document.COLUMN_LAST_MODIFIED, file.lastModified())
            add(DocumentsContract.Document.COLUMN_FLAGS, flags)
            add(DocumentsContract.Document.COLUMN_SIZE, if (file.isFile) file.length() else 0L)
        }
    }

    private fun deleteRecursively(file: File): Boolean {
        if (file.isDirectory) {
            file.listFiles()?.forEach { deleteRecursively(it) }
        }
        return file.delete()
    }
}