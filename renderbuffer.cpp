/*
Copyright (c) 2010 Noel R. Cower

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*/

#include <pub.mod/glew.mod/GL/glew.h>
#include <math.h>
#include <float.h>
#include <string.h>
#include <stdio.h>
#include <deque>
#include <iostream>

extern "C" {


#pragma mark Utility

inline bool floats_differ(float l, float r) {
	return (FLT_EPSILON<=fabsf(l-r));
}




#pragma mark brl.graphics imports

extern int brl_graphics_GraphicsSeq;




#pragma mark Constants

const size_t RENDER_BUFFER_INIT_ELEMENTS = 512;
const double RENDER_BUFFER_SCALE = 2.0;



#pragma mark Types

typedef struct s_blend_factors {
	GLenum source;
	GLenum dest;
} blend_factors_t;

typedef struct s_alpha_test {
	GLenum func;
	GLclampf ref;
} alpha_test_t;

typedef struct s_render_indices {
	uint32_t index_from;
	uint32_t indices;
	uint32_t num_indices;
} render_indices_t;

typedef std::deque<render_indices_t> render_indices_deque_t;

typedef struct s_render_state {
	GLuint texture_name;
	GLenum render_mode;
	blend_factors_t blend;
	alpha_test_t alpha;
	
	GLfloat line_width;
} render_state_t;

typedef std::deque<render_state_t> render_state_deque_t;

typedef struct s_render_buffer {
	GLfloat *vertices, *texcoords;
	GLubyte *colors;
	size_t vertices_length, texcoords_length, colors_length;
	
	uint32_t index;
	uint32_t sets;
	
	GLint *indices;
	GLsizei *counts;
	uint32_t indices_length;
	uint32_t lock;
	
	render_indices_deque_t *render_indices;
	render_state_deque_t *render_states;
} render_buffer_t;




#pragma mark Globals

static struct {
	bool state_bound;
	bool texture2D_enabled;
	GLuint texture2D_binding;
	int sequence;
	bool blend_enabled;
	bool alpha_test_enabled;
	
	render_state_t active;
} rs_globals = {
	false, false, (GLuint)0, 0, false, false,
};




#pragma mark Prototypes

// render_state_t
render_state_t *rs_init(render_state_t *rs);
render_state_t *rs_copy(render_state_t *rs, render_state_t *to);
void rs_bind(render_state_t *rs);
void rs_restore(render_state_t *rs);
void rs_set_texture(GLuint name);

// render_buffer_t

render_buffer_t *rb_new();
render_buffer_t *rb_init(render_buffer_t *rb);
void rb_destroy(render_buffer_t *rb, int free);
static void rb_new_state(render_buffer_t *rb);
void rb_set_texture(render_buffer_t *rb, GLuint name);
void rb_set_mode(render_buffer_t *rb, GLenum mode);
void rb_set_blend_func(render_buffer_t *rb, GLenum source, GLenum dest);
void rb_set_alpha_func(render_buffer_t *rb, GLenum func, GLclampf ref);
void rb_set_line_width(render_buffer_t *rb, GLfloat width);
void rb_add_vertices(render_buffer_t *rb, int elements, GLfloat *points, GLfloat *texcoords, GLubyte *colors);
void rb_lock_buffers(render_buffer_t *rb);
void rb_unlock_buffers(render_buffer_t *rb);
void rb_render(render_buffer_t *rb);
void rb_reset(render_buffer_t *rb);




#pragma mark Implementations

// render_state_t

render_state_t *rs_init(render_state_t *rs) {
	if (rs) {
		rs->texture_name = (GLuint)0;
		rs->render_mode = GL_POLYGON;
		rs->blend.source = GL_ONE;
		rs->blend.dest = GL_ZERO;
		rs->alpha.func = GL_ALWAYS;
		rs->alpha.ref = (GLclampf)0.0f;
		rs->line_width = 1.0f;
	}
	return rs;
}


void rs_destroy(render_state_t *rs, int free) {
	if (rs != NULL && free != 0) {
		delete rs;
	}
}


render_state_t *rs_copy(render_state_t *rs, render_state_t *to) {
	*to = *rs;
	return to;
}


void rs_bind(render_state_t *rs) {
	render_state_t active = rs_globals.active;
	rs_set_texture(rs->texture_name);
	
	if (!rs_globals.state_bound || rs->blend.dest != active.blend.dest ||
		rs->blend.source != active.blend.source) {
		if (rs->blend.dest == GL_ONE && rs->blend.source == GL_ZERO && rs_globals.blend_enabled) {
			glDisable(GL_BLEND);
			rs_globals.blend_enabled = false;
		} else {
			if (!rs_globals.blend_enabled) {
				glEnable(GL_BLEND);
				rs_globals.blend_enabled = true;
			}
			glBlendFunc(rs->blend.source, rs->blend.dest);
		}
	}
	
	if (!rs_globals.state_bound || rs->alpha.func != active.alpha.func || floats_differ(rs->alpha.ref, active.alpha.ref)) {
		if (rs->alpha.func == GL_ALWAYS && rs_globals.alpha_test_enabled) {
			glDisable(GL_ALPHA_TEST);
			rs_globals.alpha_test_enabled = false;
		} else {
			if (!rs_globals.alpha_test_enabled) {
				glEnable(GL_ALPHA_TEST);
				rs_globals.alpha_test_enabled = true;
			}
			glAlphaFunc(rs->alpha.func, rs->alpha.ref);
		}
	}
	
	if (rs->render_mode == GL_LINES && floats_differ(rs->line_width, active.line_width)) {
		glLineWidth(rs->line_width);
	}
	
	rs_globals.active = *rs;
	rs_globals.state_bound = true;
}


void rs_restore(render_state_t *rs) {
	render_state_t restore;
	if (rs) {
		restore = *rs;
	} else {
		restore = rs_globals.active;
	}
	
	if (rs_globals.alpha_test_enabled) {
		glEnable(GL_ALPHA_TEST);
	} else {
		glDisable(GL_ALPHA_TEST);
	}
	
	if (rs_globals.blend_enabled) {
		glEnable(GL_BLEND);
	} else {
		glDisable(GL_BLEND);
	}
	
	if (rs_globals.texture2D_enabled) {
		glEnable(GL_TEXTURE_2D);
	} else {
		glDisable(GL_TEXTURE_2D);
	}
	
	rs_bind(&restore);
}


void rs_set_texture(GLuint name) {
	if (name == rs_globals.texture2D_binding && brl_graphics_GraphicsSeq == rs_globals.sequence ) {
		return;
	}
	
	int cur_seq = brl_graphics_GraphicsSeq;
	int active_seq = rs_globals.sequence;
	
	if (name) {
		if (!rs_globals.texture2D_enabled || cur_seq != active_seq) {
			glEnable(GL_TEXTURE_2D);
			rs_globals.texture2D_enabled = true;
		}
		
		glBindTexture(GL_TEXTURE_2D, name);
	} else if (rs_globals.texture2D_enabled || cur_seq == active_seq) {
		glDisable(GL_TEXTURE_2D);
		rs_globals.texture2D_enabled = false;
	}
	rs_globals.sequence = cur_seq;
	rs_globals.texture2D_binding = name;
}


// render_buffer_t

/* // UNUSED
render_buffer_t *rb_new() {
	return rb_init(new render_buffer_t());
}
*/


render_buffer_t *rb_init(render_buffer_t *rb) {
	if (rb) {
		rb->vertices_length = RENDER_BUFFER_INIT_ELEMENTS*3;
		rb->texcoords_length = RENDER_BUFFER_INIT_ELEMENTS*2;
		rb->colors_length = RENDER_BUFFER_INIT_ELEMENTS*4;
		rb->vertices = new GLfloat[RENDER_BUFFER_INIT_ELEMENTS*3];
		rb->texcoords = new GLfloat[RENDER_BUFFER_INIT_ELEMENTS*2];
		rb->colors = new GLubyte[RENDER_BUFFER_INIT_ELEMENTS*4];
		rb->index = 0;
		rb->sets = 0;
		rb->indices_length = RENDER_BUFFER_INIT_ELEMENTS;
		rb->indices = new GLint[RENDER_BUFFER_INIT_ELEMENTS];
		rb->counts = new GLsizei[RENDER_BUFFER_INIT_ELEMENTS];
		rb->lock = 0;
		rb->render_indices = new render_indices_deque_t();
		rb->render_indices->push_front((render_indices_t){0, 0, 0});
		render_state_t init_state;
		rs_init(&init_state);
		rb->render_states = new render_state_deque_t();
		rb->render_states->push_front(init_state);
	}
	return rb;
}


void rb_destroy(render_buffer_t *rb, int free) {
	if (rb) {
		delete [] rb->vertices;
		delete [] rb->texcoords;
		delete [] rb->colors;
		delete [] rb->indices;
		delete [] rb->counts;
		if (free != 0) {
			delete rb;
		}
	}
}


static void rb_new_state(render_buffer_t *rb) {
	const render_indices_t &indices_front = rb->render_indices->front();
	if (0 < indices_front.indices) {
		rb->render_indices->push_front((render_indices_t){rb->sets, 0, 0});
		rb->render_states->push_front(rb->render_states->front());
	}
}


void rb_set_texture(render_buffer_t *rb, GLuint name) {
	if (rb->render_states->front().texture_name != name) {
		rb_new_state(rb);
		rb->render_states->front().texture_name = name;
	}
}


void rb_set_mode(render_buffer_t *rb, GLenum mode) {
	if (rb->render_states->front().render_mode != mode) {
		rb_new_state(rb);
		rb->render_states->front().render_mode = mode;
	}
}


void rb_set_blend_func(render_buffer_t *rb, GLenum source, GLenum dest) {
	blend_factors_t orig = rb->render_states->front().blend;
	if (orig.source != source || orig.dest != dest) {
		rb_new_state(rb);
		rb->render_states->front().blend = (blend_factors_t){source, dest};
	}
}


void rb_set_alpha_func(render_buffer_t *rb, GLenum func, GLclampf ref) {
	alpha_test_t orig = rb->render_states->front().alpha;
	if (orig.func != func || floats_differ(orig.ref, ref)) {
		rb_new_state(rb);
		rb->render_states->front().alpha = (alpha_test_t){func, ref};
	}
}


void rb_set_line_width(render_buffer_t *rb, GLfloat width) {
	if (floats_differ(rb->render_states->front().line_width, width)) {
		rb_new_state(rb);
		rb->render_states->front().line_width = width;
	}
}


void rb_add_vertices(render_buffer_t *rb, int elements, GLfloat *vertices, GLfloat *texcoords, GLubyte *colors) {
	if (rb->lock != 0) {
		return;
	}
	
	if (rb->indices_length <= rb->sets) {
		size_t new_size = (size_t)(rb->indices_length*RENDER_BUFFER_SCALE);
		{
			GLint *temp = new GLint[new_size];
			memcpy(temp, rb->indices, rb->indices_length*sizeof(GLint));
			delete [] rb->indices;
			rb->indices = temp;
		}
		{
			GLsizei *temp = new GLsizei[new_size];
			memcpy(temp, rb->counts, rb->indices_length*sizeof(GLsizei));
			delete [] rb->counts;
			rb->counts = temp;
		}
	}
	
	uint32_t index = rb->index;
	uint32_t set = rb->sets;
	rb->indices[set] = index;
	rb->counts[set] = elements;
	
	size_t sizereq = (size_t)(index+elements);
	
	if (rb->vertices_length < sizereq*3) {
		size_t new_size = (size_t)(rb->vertices_length*RENDER_BUFFER_SCALE);
		if (new_size < sizereq*3) {
			new_size = sizereq*3;
		}
		GLfloat *temp = new GLfloat[new_size];
		memcpy(temp, rb->vertices, sizeof(GLfloat)*rb->vertices_length);
		delete [] rb->vertices;
		rb->vertices = temp;
	}
	
	sizereq *= 2;
	if (rb->texcoords_length < sizereq) {
		size_t new_size = (size_t)(rb->texcoords_length*RENDER_BUFFER_SCALE);
		if (new_size < sizereq) {
			new_size = sizereq;
		}
		GLfloat *temp = new GLfloat[new_size];
		memcpy(temp, rb->texcoords, sizeof(GLfloat)*rb->texcoords_length);
		delete [] rb->texcoords;
		rb->texcoords = temp;
	}
	
	sizereq *= 2;
	if (rb->colors_length < sizereq) {
		size_t new_size = (size_t)(rb->colors_length*RENDER_BUFFER_SCALE);
		if (new_size < sizereq) {
			new_size = sizereq;
		}
		GLubyte *temp = new GLubyte[new_size];
		memcpy(temp, rb->colors, sizeof(GLubyte)*rb->colors_length);
		delete [] rb->colors;
		rb->colors = temp;
	}
	
	memcpy(rb->vertices+(index*3), vertices, elements*3*sizeof(GLfloat));
	if (texcoords != NULL) {
		memcpy(rb->texcoords+(index*2), texcoords, elements*2*sizeof(GLfloat));
	}
	if (colors != NULL) {
		memcpy(rb->colors+(index*4), colors, elements*4*sizeof(GLubyte));
	} else {
		memset(rb->colors+(index*4), 255, elements*4*sizeof(GLubyte));
	}
	
	rb->sets += 1;
	render_indices_t &front = rb->render_indices->front();
	front.indices += 1;
	rb->index += elements;
	front.num_indices += elements;
}


void rb_lock_buffers(render_buffer_t *rb) {
	if (rb->lock == 0 && rb->index) {
		glVertexPointer(3, GL_FLOAT, 0, rb->vertices);
		glColorPointer(4, GL_UNSIGNED_BYTE, 0, rb->colors);
		glTexCoordPointer(2, GL_FLOAT, 0, rb->texcoords);
		
		if (GLEW_EXT_compiled_vertex_array) {
			glLockArraysEXT(0, rb->index);
		}
	}
	rb->lock += 1;
}


void rb_unlock_buffers(render_buffer_t *rb) {
	if (rb->lock == 0) {
		// TODO: error?
		return;
	}
	rb->lock -= 1;
	if (rb->lock == 0 && rb->index) {
		if (GLEW_EXT_compiled_vertex_array) {
			glUnlockArraysEXT();
		}
		
		glVertexPointer(4, GL_FLOAT, 0, NULL);
		glTexCoordPointer(4, GL_FLOAT, 0, NULL);
		glColorPointer(4, GL_FLOAT, 0, NULL);
	}
}


void rb_render(render_buffer_t *rb) {
	if (rb->sets == 0) {
		return;
	}
	
	rb_lock_buffers(rb);
	
	GLint *indices_ptr = rb->indices;
	GLsizei *counts_ptr = rb->counts;
	
	render_indices_deque_t::iterator index_iter = rb->render_indices->begin();
	render_state_deque_t::iterator state_iter = rb->render_states->begin();
	
	render_indices_deque_t::iterator index_end = rb->render_indices->end();
	render_state_deque_t::iterator state_end = rb->render_states->end();
	
	if (GLEW_VERSION_1_4) {
		while (index_iter != index_end && state_iter != state_end) {
			GLint indices = index_iter->indices;

			if (indices != 0) {
				uint32_t index_from = index_iter->index_from;
				if (1 < indices) {
					glMultiDrawArrays(state_iter->render_mode, indices_ptr+index_from, counts_ptr+index_from, indices);
				} else {
					glDrawArrays(state_iter->render_mode, indices_ptr[index_from], counts_ptr[index_from]);
				}
			}
			
			++index_iter;
			++state_iter;
		}
	} else {
		while (index_iter != index_end && state_iter != state_end) {
			if (index_iter->indices == 0) {
				uint32_t index_from = index_iter->index_from;
				glDrawArrays(state_iter->render_mode, indices_ptr[index_from], counts_ptr[index_from]);
			}
			
			++index_iter;
			++state_iter;
		}
	}
	
	rb_unlock_buffers(rb);
}


void rb_reset(render_buffer_t *rb) {
	if (rb->lock != 0) {
		// TODO: error?
		return;
	}
	
	if (rb->sets == 0) {
		// nothing to do
		return;
	}
	
	rb->index = 0;
	rb->sets = 0;
	rb->render_indices->clear();
	rb->render_indices->push_front((render_indices_t){0, 0, 0});
	rb->render_states->erase(rb->render_states->begin(), rb->render_states->end()-2);
}

}
