/* LuaRaw filename/module/env boundary. No locale, codepage or drive changes. */
#ifndef PALCRAFT_UTF8_PATHS_H
#define PALCRAFT_UTF8_PATHS_H
#if defined(_WIN32)
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <wchar.h>

static wchar_t *pc_wide(const char *value) {
  int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, NULL, 0);
  wchar_t *result;
  if (!count) { errno = EILSEQ; return NULL; }
  result = (wchar_t *)malloc((size_t)count * sizeof(wchar_t));
  if (!result) { errno = ENOMEM; return NULL; }
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, result, count)) {
    free(result); errno = EILSEQ; return NULL;
  }
  return result;
}
static char *pc_utf8(const wchar_t *value) {
  int count = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value, -1, NULL, 0, NULL, NULL);
  char *result;
  if (!count) { errno = EILSEQ; return NULL; }
  result = (char *)malloc((size_t)count);
  if (!result) { errno = ENOMEM; return NULL; }
  if (!WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value, -1, result, count, NULL, NULL)) {
    free(result); errno = EILSEQ; return NULL;
  }
  return result;
}
static FILE *pc_fopen(const char *path, const char *mode) {
  wchar_t *p = pc_wide(path), *m = pc_wide(mode);
  FILE *result = p && m ? _wfopen(p, m) : NULL;
  free(p); free(m); return result;
}
static FILE *pc_freopen(const char *path, const char *mode, FILE *stream) {
  wchar_t *p = pc_wide(path), *m = pc_wide(mode);
  FILE *result = p && m ? _wfreopen(p, m, stream) : NULL;
  free(p); free(m); return result;
}
static int pc_remove(const char *path) {
  wchar_t *p = pc_wide(path);
  int result = p ? _wremove(p) : -1;
  free(p); return result;
}
static int pc_rename(const char *from, const char *to) {
  wchar_t *a = pc_wide(from), *b = pc_wide(to);
  int result = a && b ? _wrename(a, b) : -1;
  free(a); free(b); return result;
}
static char *pc_getenv_utf8(const char *name) {
  wchar_t *key = pc_wide(name), *value;
  DWORD count, used;
  char *result;
  if (!key) return NULL;
  SetLastError(ERROR_SUCCESS);
  count = GetEnvironmentVariableW(key, NULL, 0);
  if (!count) {
    DWORD error = GetLastError();
    free(key);
    if (error == ERROR_ENVVAR_NOT_FOUND) return NULL;
    if (error != ERROR_SUCCESS) return NULL;
    result = (char *)malloc(1);
    if (result) result[0] = 0;
    return result;
  }
  value = (wchar_t *)malloc((size_t)count * sizeof(wchar_t));
  if (!value) { free(key); errno = ENOMEM; return NULL; }
  used = GetEnvironmentVariableW(key, value, count);
  free(key);
  if (!used || used >= count) { free(value); return NULL; }
  result = pc_utf8(value); free(value); return result;
}
static HMODULE pc_loadlibrary(const char *path, DWORD flags) {
  wchar_t *wide = pc_wide(path);
  HMODULE result;
  DWORD error;
  if (!wide) { SetLastError(ERROR_NO_UNICODE_TRANSLATION); return NULL; }
  result = LoadLibraryExW(wide, NULL, flags);
  error = GetLastError(); free(wide); SetLastError(error); return result;
}
static char *pc_exedir_utf8(void) {
  wchar_t wide[32768], *last;
  DWORD count = GetModuleFileNameW(NULL, wide, 32768);
  if (!count || count == 32768 || (last = wcsrchr(wide, L'\\')) == NULL) return NULL;
  *last = 0;
  return pc_utf8(wide);
}
#else
#define pc_fopen fopen
#define pc_freopen freopen
#define pc_remove remove
#define pc_rename rename
#endif
#endif
