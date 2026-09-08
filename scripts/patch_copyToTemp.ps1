$path = 'c:\development\ConversionFlutter\my_flutter_app\android\app\src\main\kotlin\com\orokaconner\convertthespirereborn\MainActivity.kt'
Get-Content $path | ForEach-Object {
    if ($_ -match 'result\.error\("LIST_FAILED"') {
        $_
        '                    "copyToTemp" -> {'
        '                        val uriStr = call.argument<String>("uri")'
        '                        if (uriStr.isNullOrBlank()) {'
        '                            result.success(null)'
        '                            return@setMethodCallHandler'
        '                        }'
        '                        try {'
        '                            val srcUri = Uri.parse(uriStr)'
        '                            val input = contentResolver.openInputStream(srcUri)'
        '                            val name = DocumentFile.fromSingleUri(this, srcUri)?.name ?: "tmp"'
        '                            val dest = File(cacheDir, "saf_tmp_" + System.currentTimeMillis() + "_" + name)'
        '                            input?.use { ins ->'
        '                                dest.outputStream().use { out ->'
        '                                    ins.copyTo(out)'
        '                                }'
        '                            }'
        '                            result.success(dest.absolutePath)'
        '                        } catch (e: Exception) {'
        '                            result.error("COPY_FAILED", e.message, null)'
        '                        }'
        '                    }'
    } else {
        $_
    }
} | Set-Content $path
