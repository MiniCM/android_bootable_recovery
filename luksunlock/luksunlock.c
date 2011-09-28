#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <linux/input.h>

#include "minui/minui.h"

#define CRYPTSETUP		"/system/xbin/cryptsetup"

#define SDCARD_DEVICE		"/dev/block/mmcblk0p1"
#define DATA_DEVICE		"/dev/block/loop1"

#define SDCARD_MAPPER_NAME	"sdcard-enc"
#define DATA_MAPPER_NAME	"data-enc"

#define CHAR_WIDTH		10
#define CHAR_HEIGHT		18

#define CHAR_START		0x20
#define CHAR_END		0x7E

struct keymap {
	unsigned char key;
	int xpos;
	int ypos;
	int selected;
};

struct keymap keys[CHAR_END - CHAR_START];
struct input_event keyqueue[2048];

char passphrase[1024];

pthread_mutex_t keymutex;
unsigned int sp = 0;

gr_surface background;
int res, current = 0;
int first_pass = 1;

char *escape_input(char *str) {
	size_t i, j = 0;
	char *new = malloc(sizeof(char) * (strlen(str) * 2 + 1));

	for(i = 0; i < strlen(str); i++) {
		if(!(((str[i] >= 'A') && (str[i] <= 'Z')) ||
		((str[i] >= 'a') && (str[i] <= 'z')) ||
		((str[i] >= '0') && (str[i] <= '9')) )) {
			new[j] = '\\';
			j++;
		}
		new[j] = str[i];
		j++;
	}
	new[j] = '\0';

	return new;
}

void draw_keymap() {
	size_t i;
	char keybuf[2];

	for(i = 0; i < (CHAR_END - CHAR_START); i++) {
		sprintf(keybuf, "%c", keys[i].key);

		if(keys[i].selected == 1) {
			//gr_color(255, 0, 0, 255); //red
			gr_color(0, 255, 255, 255); //cyan highlighted
			gr_fill(keys[i].xpos +10, keys[i].ypos - CHAR_HEIGHT, keys[i].xpos + CHAR_WIDTH + 10, keys[i].ypos);
			//gr_color(255, 255, 255, 255); //white
			gr_color(0, 0, 0, 255); //black 
		}
		else
			//gr_color(0, 0, 0, 255); //black
			gr_color(255, 255, 255, 255); //white
			

		gr_text(keys[i].xpos + 10, keys[i].ypos, keybuf);
	}
}

static void *input_thread() {
	int rel_sum = 0;

	for(;;) {
		struct  input_event ev;

		do {
			ev_get(&ev, 0);

			switch(ev.type) {
				case EV_SYN:
					continue;
				case EV_REL:
					rel_sum += ev.value;
					break;

				default:
					rel_sum = 0;
			}

			if(rel_sum > 4 || rel_sum < -4)
				break;

		} while(ev.type != EV_KEY || ev.code > KEY_MAX);

		rel_sum = 0;

		// Add the key to the fifo
		pthread_mutex_lock(&keymutex);
		if(sp < (sizeof(keyqueue) / sizeof(struct input_event)))
			sp++;

		keyqueue[sp] = ev;
		pthread_mutex_unlock(&keymutex);
	}

	return 0;
}

void ui_init(void) {
	gr_init();
	ev_init();

	// Generate bitmap from /system/res/padlock.png ( you can change the path in minui/resources.c)
	res_create_surface("padlock", &background);
}

void draw_screen() {
	int bgwidth, bgheight, bgxpos, bgypos, i, cols;

	//gr_color(0, 0, 0, 255); //black
	gr_color(255, 255, 255, 255); //white 
	gr_fill(0, 0, gr_fb_width(), gr_fb_height());

	bgwidth = gr_get_width(background);
	bgheight = gr_get_height(background);
	bgxpos = (gr_fb_width() - gr_get_width(background)) / 2;
	bgypos = (gr_fb_height() - gr_get_height(background)) / 2;

	gr_blit(background, 0, 0, bgwidth, bgheight, bgxpos, bgypos);

	gr_text(10, CHAR_HEIGHT, "Enter password: ");

	cols = gr_fb_width() / CHAR_WIDTH;

	for(i = 0; i < (int) strlen(passphrase); i++) 
		gr_text(i * CHAR_WIDTH + 10, CHAR_HEIGHT * 2, "*");

	for(; i < cols - 1; i++)
		gr_text(i * CHAR_WIDTH +10, CHAR_HEIGHT * 2, "_");

	gr_text(10, gr_fb_height() - CHAR_HEIGHT, "Home to select, Camera to erase");
	gr_text(10, gr_fb_height(), "Power button to unlock");

	draw_keymap();
	gr_flip();
}

void generate_keymap() {
	int xpos, ypos;
	char key;
	int i;

	xpos = 0;
	ypos = CHAR_HEIGHT * 4;

	for(i = 0, key = CHAR_START; key < CHAR_END; key++, i++, xpos += (CHAR_WIDTH * 3)) {
		if(xpos >= gr_fb_width() - CHAR_WIDTH) {
			ypos += CHAR_HEIGHT;

			xpos = 0;
		}

		keys[i].key = key;
		keys[i].xpos = xpos;
		keys[i].ypos = ypos;
		keys[i].selected = 0;
	}

	keys[current].selected = 1;
}

void unlock() {
	char buffer[2048];
	int fd, failed = 0;

	gr_color(0, 0, 0, 255);
	gr_fill(0, 0, gr_fb_width(), gr_fb_height());
	gr_color(255, 255, 255, 255);

	gr_text((gr_fb_width() / 2) - ((strlen("Unlocking...") / 2) * CHAR_WIDTH), gr_fb_height() / 2, "Unlocking...");
	gr_flip();

	/*snprintf(buffer, sizeof(buffer) - 1, "echo %s | %s luksOpen %s %s", escape_input(passphrase), CRYPTSETUP, SDCARD_DEVICE, SDCARD_MAPPER_NAME);
	system(buffer);*/

	snprintf(buffer, sizeof(buffer) - 1, "echo %s | %s luksOpen %s %s", escape_input(passphrase), CRYPTSETUP, DATA_DEVICE, DATA_MAPPER_NAME);
	system(buffer);

	/*snprintf(buffer, sizeof(buffer) - 1, "/dev/mapper/%s", SDCARD_MAPPER_NAME);
	fd = open(buffer, 0);
	if(fd < 0)
		failed = 1;*/

	snprintf(buffer, sizeof(buffer) - 1, "/dev/mapper/%s", DATA_MAPPER_NAME);
	fd = open(buffer, 0);
	if(fd < 0)
		failed = 1;

	if(!failed) {
		gr_text((gr_fb_width() / 2) - ((strlen("Success!") / 2) * CHAR_WIDTH), gr_fb_height() / 2 + CHAR_HEIGHT, "Success!");
		gr_flip();
		exit(0);
	}

	gr_text((gr_fb_width() / 2) - ((strlen("Failed!") / 2) * CHAR_WIDTH), gr_fb_height() / 2 + CHAR_HEIGHT, "Failed!");
	gr_flip();

	sleep(2);
	passphrase[0] = '\0';
}

void handle_key(struct input_event event) {
	int cols;
	cols = gr_fb_width() / (CHAR_WIDTH * 3);
	keys[current].selected = 0;

	// Volume down 
	if(event.type == EV_KEY && event.code == KEY_VOLUMEDOWN) {
		if(current + cols < (CHAR_END - CHAR_START))
				current += cols;
	}
	
	// Volume up 
	if(event.type == EV_KEY && event.code == KEY_VOLUMEUP) {
		if(current - cols > 0)
			current -= cols;
	}

	// Back btn
	if(event.type == EV_KEY && event.code == KEY_BACK) {
		if(current < (CHAR_END - CHAR_START) - 1)
			current++;
	}
	
	// Menu btn
	if(event.type == EV_KEY && event.code == KEY_MENU) {
		if(current > 0)
			current--;
	}

	keys[current].selected = 1;

	// Pressed menu btn
	if(event.type == EV_KEY && event.code == KEY_HOME) {
		if (first_pass == 1) {
			first_pass = 0;
		}
		else
			snprintf(passphrase, sizeof(passphrase) - 1, "%s%c", passphrase, keys[current].key);
	}

	// Pressed camera btn
	if(event.type == EV_KEY && event.code == KEY_CAMERA)
		passphrase[strlen(passphrase) - 1] = '\0';

	// Pressed power btn
	if(event.type == EV_KEY && event.code == KEY_POWER) {
#ifdef UNLOCK
		unlock();
#else
		char buffer[2048];
		int fd, failed = 0;
		gr_color(0, 0, 0, 255);
		gr_fill(0, 0, gr_fb_width(), gr_fb_height());
		gr_color(255, 255, 255, 255);
		gr_text((gr_fb_width() / 2) - ((strlen("Processing...") / 2) * CHAR_WIDTH), gr_fb_height() / 2, "Processing...");
		gr_flip();
		printf("%s", escape_input(passphrase));
		exit(0);
#endif
	}

	draw_screen();
	first_pass = 0;
}

int main(int argc, char **argv, char **envp) {
	struct input_event event;
	pthread_t t;
	unsigned int i, key_up = 0;

	ui_init();
	generate_keymap();
	draw_screen();

	pthread_create(&t, NULL, input_thread, NULL);
	pthread_mutex_init(&keymutex, NULL);
	for(;;) {
		pthread_mutex_lock(&keymutex);

		if(sp > 0) {
			for(i = 0; i < sp; i++)
				keyqueue[i] = keyqueue[i + 1];

			event = keyqueue[0];
			sp--;

			pthread_mutex_unlock(&keymutex);
		} else {
			pthread_mutex_unlock(&keymutex);
			continue;
		}

		switch(event.type) {
			case(EV_KEY):
				if(key_up == 1) {
					key_up = 0;
					break;
				}
				key_up = 1;
			case(EV_REL):
				handle_key(event);
				break;
			case(EV_SYN):
				break;
		}
	}

	return 0;
}
