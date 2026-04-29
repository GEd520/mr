class FileUtils {
  static String getExtension(String path) {
    final lastDot = path.lastIndexOf('.');
    if (lastDot == -1) return '';
    return path.substring(lastDot).toLowerCase();
  }

  static String getFileName(String path) {
    final lastSeparator = path.lastIndexOf(RegExp(r'[/\\]'));
    if (lastSeparator == -1) return path;
    return path.substring(lastSeparator + 1);
  }

  static String getFileNameWithoutExtension(String path) {
    final fileName = getFileName(path);
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot == -1) return fileName;
    return fileName.substring(0, lastDot);
  }

  static bool isBookFile(String path) {
    final ext = getExtension(path);
    return ['.txt', '.epub', '.pdf'].contains(ext);
  }

  static bool isComicFile(String path) {
    final ext = getExtension(path);
    return ['.zip', '.cbz', '.cbr', '.rar'].contains(ext);
  }

  static bool isMediaFile(String path) {
    final ext = getExtension(path);
    return ['.mp4', '.mkv', '.avi', '.mp3', '.m4a', '.flac'].contains(ext);
  }

  static bool isDanFile(String path) {
    return getExtension(path) == '.dan';
  }
}
