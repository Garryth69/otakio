/* Otakio: converts a page image (JPEG, PNG or WebP) to JPEG, PNG or WebP at full resolution.
 * Decoding happens in main memory (no GPU texture size limit). Used by "Save image". */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <setjmp.h>
#include <jpeglib.h>
#include <png.h>
#include <webp/decode.h>
#include <webp/encode.h>

static unsigned char *read_file(const char *path, size_t *size) {
	FILE *f = fopen(path, "rb");
	if (!f)
		return NULL;
	fseek(f, 0, SEEK_END);
	long n = ftell(f);
	fseek(f, 0, SEEK_SET);
	unsigned char *data = n > 0 ? (unsigned char *)malloc(n) : NULL;
	if (data && fread(data, 1, n, f) != (size_t)n) {
		free(data);
		data = NULL;
	}
	fclose(f);
	*size = data ? (size_t)n : 0;
	return data;
}

struct jerr {
	struct jpeg_error_mgr pub;
	jmp_buf jump;
};

static void jerr_exit(j_common_ptr cinfo) {
	longjmp(((struct jerr *)cinfo->err)->jump, 1);
}

/* returns a malloc'd RGB buffer (3 bytes per pixel) */
static unsigned char *decode_jpeg(const unsigned char *data, size_t size, int *w, int *h) {
	struct jpeg_decompress_struct cinfo;
	struct jerr err;
	unsigned char *volatile rgb = NULL;
	cinfo.err = jpeg_std_error(&err.pub);
	err.pub.error_exit = jerr_exit;
	if (setjmp(err.jump)) {
		jpeg_destroy_decompress(&cinfo);
		free(rgb);
		return NULL;
	}
	jpeg_create_decompress(&cinfo);
	jpeg_mem_src(&cinfo, (unsigned char *)data, size);
	jpeg_read_header(&cinfo, TRUE);
	cinfo.out_color_space = JCS_RGB;
	jpeg_start_decompress(&cinfo);
	*w = cinfo.output_width;
	*h = cinfo.output_height;
	rgb = (unsigned char *)malloc((size_t)*w * *h * 3);
	if (!rgb) {
		jpeg_destroy_decompress(&cinfo);
		return NULL;
	}
	while (cinfo.output_scanline < cinfo.output_height) {
		JSAMPROW row = rgb + (size_t)cinfo.output_scanline * *w * 3;
		jpeg_read_scanlines(&cinfo, &row, 1);
	}
	jpeg_finish_decompress(&cinfo);
	jpeg_destroy_decompress(&cinfo);
	return rgb;
}

static unsigned char *decode_png(const unsigned char *data, size_t size, int *w, int *h) {
	png_image image;
	memset(&image, 0, sizeof(image));
	image.version = PNG_IMAGE_VERSION;
	if (!png_image_begin_read_from_memory(&image, data, size))
		return NULL;
	image.format = PNG_FORMAT_RGB;
	unsigned char *rgb = (unsigned char *)malloc(PNG_IMAGE_SIZE(image));
	if (!rgb || !png_image_finish_read(&image, NULL, rgb, 0, NULL)) {
		png_image_free(&image);
		free(rgb);
		return NULL;
	}
	*w = image.width;
	*h = image.height;
	return rgb;
}

static int write_jpeg(const char *path, const unsigned char *rgb, int w, int h, int quality) {
	FILE *f = fopen(path, "wb");
	if (!f)
		return 0;
	struct jpeg_compress_struct cinfo;
	struct jerr err;
	cinfo.err = jpeg_std_error(&err.pub);
	err.pub.error_exit = jerr_exit;
	if (setjmp(err.jump)) {
		jpeg_destroy_compress(&cinfo);
		fclose(f);
		return 0;
	}
	jpeg_create_compress(&cinfo);
	jpeg_stdio_dest(&cinfo, f);
	cinfo.image_width = w;
	cinfo.image_height = h;
	cinfo.input_components = 3;
	cinfo.in_color_space = JCS_RGB;
	jpeg_set_defaults(&cinfo);
	jpeg_set_quality(&cinfo, quality, TRUE);
	jpeg_start_compress(&cinfo, TRUE);
	while (cinfo.next_scanline < cinfo.image_height) {
		JSAMPROW row = (JSAMPROW)(rgb + (size_t)cinfo.next_scanline * w * 3);
		jpeg_write_scanlines(&cinfo, &row, 1);
	}
	jpeg_finish_compress(&cinfo);
	jpeg_destroy_compress(&cinfo);
	fclose(f);
	return 1;
}

static int write_png(const char *path, const unsigned char *rgb, int w, int h) {
	png_image image;
	memset(&image, 0, sizeof(image));
	image.version = PNG_IMAGE_VERSION;
	image.width = w;
	image.height = h;
	image.format = PNG_FORMAT_RGB;
	return png_image_write_to_file(&image, path, 0, rgb, 0, NULL) != 0;
}

static int write_webp(const char *path, const unsigned char *rgb, int w, int h, int quality) {
	uint8_t *out = NULL;
	size_t size = WebPEncodeRGB(rgb, w, h, w * 3, (float)quality, &out);
	if (!size)
		return 0;
	FILE *f = fopen(path, "wb");
	int ok = f && fwrite(out, 1, size, f) == size;
	if (f)
		fclose(f);
	WebPFree(out);
	return ok;
}

/* to: 0 = JPEG, 1 = PNG, 2 = WebP. Returns 1 on success. */
int otakio_convert_image(const char *src, const char *dst, int to, int quality) {
	size_t size = 0;
	unsigned char *data = read_file(src, &size);
	if (!data)
		return 0;
	int w = 0, h = 0, from_webp = 0;
	unsigned char *rgb = NULL;
	if (size > 12 && !memcmp(data, "RIFF", 4) && !memcmp(data + 8, "WEBP", 4)) {
		rgb = WebPDecodeRGB(data, size, &w, &h);
		from_webp = 1;
	} else if (size > 8 && data[0] == 0x89 && data[1] == 'P' && data[2] == 'N' && data[3] == 'G') {
		rgb = decode_png(data, size, &w, &h);
	} else if (size > 3 && data[0] == 0xFF && data[1] == 0xD8) {
		rgb = decode_jpeg(data, size, &w, &h);
	}
	free(data);
	if (!rgb)
		return 0;
	if (quality <= 0 || quality > 100)
		quality = 92;
	int ok = to == 1 ? write_png(dst, rgb, w, h) : to == 2 ? write_webp(dst, rgb, w, h, quality) : write_jpeg(dst, rgb, w, h, quality);
	if (from_webp)
		WebPFree(rgb);
	else
		free(rgb);
	return ok;
}
