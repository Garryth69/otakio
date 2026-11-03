/* The SDK's OpenSSL 1.1.1 is built without the console UI (no terminal on the Vita).
   libcurl only asks for it to prompt for client-certificate passwords, which lpp never uses. */
#include <openssl/ui.h>
UI_METHOD *UI_OpenSSL(void) { return (UI_METHOD *)UI_null(); }
