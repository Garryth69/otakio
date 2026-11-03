// Otakio: native WebP support for piclib (libwebp). Sites serve most covers/pages as WebP and
// the online converters block some domains, so the console decodes them itself.
#include <stdlib.h>
#include <string.h>
#include <vitasdk.h>
#include <vita2d.h>
#include <webp/decode.h>

#define WEBP_MAX_TEXTURE_SIZE 4096

int is_WEBP_file(const char *filename)
{
	unsigned char head[12];
	SceUID fd = sceIoOpen(filename, SCE_O_RDONLY, 0777);
	if (fd < 0)
		return 0;
	int n = sceIoRead(fd, head, 12);
	sceIoClose(fd);
	return n == 12 && memcmp(head, "RIFF", 4) == 0 && memcmp(head + 8, "WEBP", 4) == 0;
}

static unsigned char *read_whole(const char *filename, size_t *size)
{
	SceUID fd = sceIoOpen(filename, SCE_O_RDONLY, 0777);
	if (fd < 0)
		return NULL;
	SceOff len = sceIoLseek(fd, 0, SCE_SEEK_END);
	sceIoLseek(fd, 0, SCE_SEEK_SET);
	if (len <= 0 || len > 64 * 1024 * 1024)
	{
		sceIoClose(fd);
		return NULL;
	}
	unsigned char *buf = (unsigned char *)malloc((size_t)len);
	if (!buf)
	{
		sceIoClose(fd);
		return NULL;
	}
	size_t got = 0;
	while (got < (size_t)len)
	{
		int r = sceIoRead(fd, buf + got, (SceSize)((size_t)len - got));
		if (r <= 0)
			break;
		got += (size_t)r;
	}
	sceIoClose(fd);
	if (got != (size_t)len)
	{
		free(buf);
		return NULL;
	}
	*size = got;
	return buf;
}

void get_WEBP_resolution(const char *filename, int *dest_width, int *dest_height)
{
	unsigned char head[64];
	*dest_width = -1;
	*dest_height = -1;
	SceUID fd = sceIoOpen(filename, SCE_O_RDONLY, 0777);
	if (fd < 0)
		return;
	int n = sceIoRead(fd, head, sizeof(head));
	sceIoClose(fd);
	int w, h;
	if (n > 0 && WebPGetInfo(head, (size_t)n, &w, &h))
	{
		*dest_width = w;
		*dest_height = h;
	}
}

// Decodes the region (x, y, width, height) scaled down by `denom` straight into a new texture
static vita2d_texture *decode_webp(const unsigned char *data, size_t size, int x, int y, int width, int height, int denom)
{
	WebPDecoderConfig config;
	if (!WebPInitDecoderConfig(&config))
		return NULL;
	int crop = x != 0 || y != 0 || width != 0 || height != 0;
	if (WebPGetFeatures(data, size, &config.input) != VP8_STATUS_OK)
		return NULL;
	int srcW = crop ? width : config.input.width;
	int srcH = crop ? height : config.input.height;
	int outW = srcW / denom, outH = srcH / denom;
	if (outW < 1 || outH < 1)
		return NULL;
	if (crop)
	{
		config.options.use_cropping = 1;
		config.options.crop_left = x;
		config.options.crop_top = y;
		config.options.crop_width = width;
		config.options.crop_height = height;
	}
	if (denom > 1)
	{
		config.options.use_scaling = 1;
		config.options.scaled_width = outW;
		config.options.scaled_height = outH;
	}
	vita2d_texture *texture = vita2d_create_empty_texture_format(outW, outH, SCE_GXM_TEXTURE_FORMAT_U8U8U8U8_ABGR);
	if (!texture)
		return NULL;
	config.output.colorspace = MODE_RGBA;
	config.output.is_external_memory = 1;
	config.output.u.RGBA.rgba = (uint8_t *)vita2d_texture_get_datap(texture);
	config.output.u.RGBA.stride = (int)vita2d_texture_get_stride(texture);
	config.output.u.RGBA.size = (size_t)config.output.u.RGBA.stride * outH;
	if (WebPDecode(data, size, &config) != VP8_STATUS_OK)
	{
		WebPFreeDecBuffer(&config.output);
		vita2d_free_texture(texture);
		return NULL;
	}
	WebPFreeDecBuffer(&config.output);
	return texture;
}

static int pick_denom(int width, int height, int level)
{
	float sw = (float)width / WEBP_MAX_TEXTURE_SIZE, sh = (float)height / WEBP_MAX_TEXTURE_SIZE;
	float scale = sw > sh ? sw : sh;
	if (scale < level)
		scale = (float)level;
	if (scale <= 1.f)
		return 1;
	if (scale <= 2.f)
		return 2;
	if (scale <= 4.f)
		return 4;
	if (scale <= 8.f)
		return 8;
	return 0;
}

vita2d_texture *load_WEBP_file_downscaled(const char *filename, int level)
{
	size_t size = 0;
	unsigned char *data = read_whole(filename, &size);
	if (!data)
		return NULL;
	int w, h;
	vita2d_texture *texture = NULL;
	if (WebPGetInfo(data, size, &w, &h))
	{
		int denom = pick_denom(w, h, level);
		if (denom)
			texture = decode_webp(data, size, 0, 0, 0, 0, denom);
	}
	free(data);
	return texture;
}

vita2d_texture *load_WEBP_file_part(const char *filename, int x, int y, int width, int height)
{
	if (x < 0 || y < 0 || width <= 0 || height <= 0)
		return NULL;
	size_t size = 0;
	unsigned char *data = read_whole(filename, &size);
	if (!data)
		return NULL;
	int w, h;
	vita2d_texture *texture = NULL;
	if (WebPGetInfo(data, size, &w, &h) && x + width <= w && y + height <= h)
	{
		int denom = pick_denom(width, height, 1);
		if (denom)
			texture = decode_webp(data, size, x, y, width, height, denom);
	}
	free(data);
	return texture;
}
