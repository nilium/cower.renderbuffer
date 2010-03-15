Rem
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
EndRem

SuperStrict

Module Cower.RenderBuffer

Import Brl.Graphics
'Import Brl.LinkedList
Import Pub.Glew

Import "renderbuffer.cpp"

Private

Extern "C"
	'renderstate
	Function rs_init@Ptr(rs@Ptr)
	Function rs_copy@Ptr(from@Ptr, to_@Ptr)
	Function rs_bind(rs@Ptr)
	Function rs_restore(rs@Ptr)
	Function rs_set_texture(name%)
	'renderbuffer
	Function rb_init@Ptr(rb@Ptr)
	Function rb_destroy@Ptr(rb@Ptr, free%)
	Function rb_set_texture(rb@Ptr, name%)
	Function rb_set_mode(rb@Ptr, mode%)
	Function rb_set_blend_func(rb@Ptr, source%, dest%)
	Function rb_set_alpha_func(rb@Ptr, func%, ref#)
	Function rb_set_scissor_test(rb@Ptr, enabled%, x%, y%, w%, h%)
	Function rb_set_line_width(rb@Ptr, width#)
	Function rb_add_vertices(rb@Ptr, elements%, vertices@Ptr, texcoords@Ptr, colors@Ptr)
	Function rb_lock_buffers(rb@Ptr)
	Function rb_unlock_buffers(rb@Ptr)
	Function rb_render(rb@Ptr)
	Function rb_reset(rb@Ptr)
End Extern

Public

Type TRenderState Final
	Field texture_name%
	Field render_mode%
	Field blend_source%
	Field blend_dest%
	Field alpha_func%
	Field alpha_ref#
	Field sc_enabled%
	Field sc_x%, sc_y%
	Field sc_w%, sc_h%
	Field line_width#
	
	Method New()
		rs_init(Self)
	End Method
	
	Method Bind()
		rs_bind(Self)
	End Method
	
	Method Restore()
		rs_restore(Self)
	End Method
	
	Method Clone:TRenderState()
		Local c:TRenderState = New TRenderState
		rs_copy(Self, c)
		Return c
	End Method
	
	Function SetTexture(tex%)
		rs_set_texture(tex)
	End Function
	
	Function RestoreState(state:TRenderState=Null)
		If state = Null Then
			rs_restore(Null)
		Else
			rs_restore(state)
		EndIf
	End Function
End Type

Type TRenderBuffer Final
	Field _vertices@Ptr, _texcoords@Ptr, _colors@Ptr
	Field _vertices_len%, _texcoords_len%, _colors_len%
	Field _index%, _sets%
	Field _indices@Ptr, _counts@Ptr
	Field _indices_length%
	Field _lock%
	Field _render_indices@Ptr
	Field _render_states@Ptr
	
	Method New()
		rb_init(Self)
	End Method
	
	Method Delete()
		rb_destroy(Self, False)
	End Method
	
	Method SetTexture(name:Int)
		rb_set_texture(Self, name)
	End Method
	
	Method SetMode(mode:Int)
		rb_set_mode(Self, mode)
	End Method
	
	Method SetBlendFunc(source:Int, dest:Int)
		rb_set_blend_func(Self, source, dest)
	End Method
	
	Method SetAlphaFunc(func:Int, ref:Float)
		rb_set_alpha_func(Self, func, ref)
	End Method
	
	Method SetScissorTest(enabled%, x%, y%, w%, h%)
		rb_set_scissor_test(Self, enabled, x, y, w, h)
	End Method
	
	Method SetLineWidth(width#)
		rb_set_line_width(Self, width)
	End Method
 
	Method AddVerticesEx(elements%, vertices@Ptr, texcoords@Ptr, colors@Ptr)
		rb_add_vertices(Self, elements, vertices, texcoords, colors)
	End Method
	
	Method LockBuffers()
		rb_lock_buffers(Self)
	End Method
 
	Method UnlockBuffers()
		rb_unlock_buffers(Self)
	End Method
 
	Method Render()
		rb_render(Self)
	End Method
 
	Method Reset()
		rb_reset(Self)
	End Method
End Type


Rem

Private

Function FloatsDiffer:Int(a:Float, b:Float) NoDebug
	Const FLOAT_EPSILON:Float = 5.96e-08
	a:-b
	Return -FLOAT_EPSILON < a And a < FLOAT_EPSILON
End Function

Type TRenderIndices
	Field indexFrom:Int = 0
	Field indices:Int = 0
	Field numIndices:Int = 0
End Type

Public

Type TRenderState
	Field textureName:Int = 0	' may be zero
	
	Field renderMode:Int = GL_POLYGON' GL_POLYGON, etc.
	
	Field blendSource:Int = GL_ONE
	Field blendDest:Int = GL_ZERO
	
	Field alphaFunc:Int = GL_ALWAYS
	Field alphaRef:Float = 0 'GLclampf
	
	Field lineWidth:Float = 1
	
	Method Bind()
		If _current = Self Then
			Return
		EndIf
		
		SetTexture(textureName)
		
		If Not _current Or blendDest <> _current.blendDest Or blendSource <> _current.blendSource Then
			If blendDest = GL_ONE And blendDest = GL_ZERO And _blendEnabled Then
				glDisable(GL_BLEND)
				_blendEnabled = False
			Else
				If Not _blendEnabled Then
					glEnable(GL_BLEND)
					_blendEnabled = True
				EndIf
				glBlendFunc(blendSource, blendDest)
			EndIf
		EndIf
		
		If Not _current Or alphaFunc <> _current.alphaFunc Or FloatsDiffer(alphaRef, _current.alphaRef) Then
			If alphaFunc = GL_ALWAYS And _alphaTestEnabled Then
				glDisable(GL_ALPHA_TEST)
				_alphaTestEnabled = False
			Else
				If Not _alphaTestEnabled Then
					glEnable(GL_ALPHA_TEST)
					_alphaTestEnabled = True
				EndIf
				glAlphaFunc(alphaFunc, alphaRef)
			EndIf
		EndIf
		
		If renderMode = GL_LINES And FloatsDiffer(lineWidth, _current.lineWidth) Then
			glLineWidth(lineWidth)
		EndIf
		
		_current = Clone()
	End Method
	
	Method Restore()
		RestoreState(Self)
	End Method
	
	Method Clone:TRenderState()
		Local c:TRenderState = New TRenderState
		MemCopy(Varptr c.textureName, Varptr textureName, SizeOf(TRenderState))
		Return c
	End Method
	
	Global _current:TRenderState
	Global _texture2DEnabled:Int = False
	Global _activeTexture:Int = 0
	Global _atexSeq:Int = 0
	Global _blendEnabled:Int = False
	Global _alphaTestEnabled:Int = False
	
	Function SetTexture(tex%)
		If tex = _activeTexture And _atexSeq = GraphicsSeq Then
			Return
		EndIf
		
		If tex Then
			If Not _texture2DEnabled Or _atexSeq <> GraphicsSeq Then
				glEnable(GL_TEXTURE_2D)
				_texture2DEnabled = True
			EndIf
			glBindTexture(GL_TEXTURE_2D, tex)
		ElseIf _texture2DEnabled Or _atexSeq = GraphicsSeq Then
			glDisable(GL_TEXTURE_2D)
			_texture2DEnabled = False
		EndIf
		_atexSeq = GraphicsSeq
		_activeTexture = tex
	End Function
	
	Function RestoreState(state:TRenderState=Null)
		If state = Null Then
			If _current Then
				state = _current
			Else
				state = New TRenderState
			EndIf
		EndIf
		_current = Null
		
		' this is also evil
		If _alphaTestEnabled Then
			glEnable(GL_ALPHA_TEST)
		Else
			glDisable(GL_ALPHA_TEST)
		EndIf
		
		If _blendEnabled Then
			glEnable(GL_BLEND)
		Else
			glDisable(GL_BLEND)
		EndIf
		
		If _atexSeq = GraphicsSeq And _texture2DEnabled And _activeTexture Then
			glBindTexture(GL_TEXTURE_2D, _activeTexture)
		Else
			_activeTexture = 0
		EndIf
		
		If _texture2DEnabled Then
			glEnable(GL_TEXTURE_2D)
		Else
			glDisable(GL_TEXTURE_2D)
		EndIf
		
		state.Bind()
	End Function
End Type

Assert 1.005 <= TRenderBuffer.RENDER_BUFFER_SCALE Else "Insufficient scale for renderbuffer resizing"
Type TRenderBuffer
	Const RENDER_BUFFER_SIZE_BYTES:Int = 32768 '32kb
	Const RENDER_BUFFER_SCALE# = 2 ' The amount by which buffer size is multiplied when resizing
 
	Field _vertbuffer@Ptr, _vertbuffer_size%
	Field _texcoordbuffer@Ptr, _texcoordbuffer_size%
	Field _colorbuffer@Ptr, _colorbuffer_size%

	Field _index:Int = 0, _sets%=0
	Field _arrindices:Int[], _arrcounts:Int[]
	Field _lock%=0
	
	Field _renderIndexStack:TList
	Field _indexTop:TRenderIndices
	
	Field _renderStateStack:TList
	Field _stateTop:TRenderState
 
	Method New()
		_vertbuffer_size = RENDER_BUFFER_SIZE_BYTES
		_colorbuffer_size = RENDER_BUFFER_SIZE_BYTES
		_texcoordbuffer_size = RENDER_BUFFER_SIZE_BYTES
		_vertbuffer = MemAlloc(_vertbuffer_size)
		_texcoordbuffer = MemAlloc(_texcoordbuffer_size)
		_colorbuffer = MemAlloc(_colorbuffer_size)
		
		_arrindices = New Int[512]
		_arrcounts = New Int[512]
		
		_stateTop = New TRenderState
		_renderStateStack = New TList
		_renderStateStack.AddLast(_stateTop)
		
		_indexTop = New TRenderIndices
		_renderIndexStack = New TList
		_renderIndexStack.AddLast(_indexTop)
	End Method
	
	Method Delete()
		MemFree(_vertbuffer)
		MemFree(_texcoordbuffer)
		MemFree(_colorbuffer)
	End Method
	
	' Add a new state/index 
	Method _newState()
		If _indexTop.indices Then
			_indexTop = New TRenderIndices
			_indexTop.indexFrom = _sets
			_renderIndexStack.AddLast(_indexTop)
			
			_stateTop = _stateTop.Clone()
			_renderStateStack.AddLast(_stateTop)
		EndIf
	End Method
	
	Method SetTexture(tex:Int)
		If _stateTop.textureName <> tex Then
			_newState()
			_stateTop.textureName = tex
		EndIf
	End Method
	
	Method SetMode(mode:Int)
		If _stateTop.renderMode <> mode Then
			_newState()
			_stateTop.renderMode = mode
		EndIf
	End Method
	
	Method SetBlendFunc(sfac:Int, dfac:Int)
		If _stateTop.blendSource <> sfac Or _stateTop.blendDest <> dfac Then
			_newState()
			_stateTop.blendSource = sfac
			_stateTop.blendDest = dfac
		EndIf
	End Method
	
	Method SetAlphaFunc(func:Int, ref:Float)
		If _stateTop.alphaFunc <> func Or FloatsDiffer(_stateTop.alphaRef, ref) Then
			_newState()
			_stateTop.alphaFunc = func
			_stateTop.alphaRef = ref
		EndIf
	End Method
	
	Method SetLineWidth(width#)
		If FloatsDiffer(_stateTop.lineWidth, width) Then
			_newState()
			_stateTop.lineWidth = width
		EndIf
	End Method
 
	Method AddVerticesEx(elements%, points@Ptr, texcoords@Ptr, colors@Ptr)
		Assert _lock=0 Else "Buffers are locked for rendering"
		Assert points Else "Must at least provide point data"
		
		If _sets >= _arrindices.Length Then
			_arrindices = _arrindices[.. _arrindices.Length*RENDER_BUFFER_SCALE]
			_arrcounts = _arrcounts[.. _arrcounts.Length*RENDER_BUFFER_SCALE]
		EndIf
		
		_arrindices[_sets] = _index
		_arrcounts[_sets] = elements
		
		' TODO: find a prettier way to write this
		Local sizereq% = (_index+elements)*4
		
		If _vertbuffer_size < sizereq*3 Then
			Local newsize% = _vertbuffer_size*RENDER_BUFFER_SCALE
			If newsize < sizereq*3 Then
				newsize = sizereq*3
			EndIf
			_vertbuffer = MemExtend(_vertbuffer, _vertbuffer_size, newsize)
			_vertbuffer_size = newsize
			Assert _vertbuffer Else "Unable to resize vertex buffer"
		EndIf
		
		If _texcoordbuffer_size < sizereq*2 Then
			Local newsize% = _texcoordbuffer_size*RENDER_BUFFER_SCALE
			If newsize < sizereq*2 Then
				newsize = sizereq*2
			EndIf
			_texcoordbuffer = MemExtend(_texcoordbuffer, _texcoordbuffer_size, newsize)
			_texcoordbuffer_size = newsize
			Assert _texcoordbuffer Else "Unable to resize texture coordinate buffer"
		EndIf
		
		If _colorbuffer_size < sizereq Then
			Local newsize% = _colorbuffer_size*RENDER_BUFFER_SCALE
			If newsize < sizereq Then
				newsize = sizereq
			EndIf
			_colorbuffer = MemExtend(_colorbuffer, _colorbuffer_size, newsize)
			_colorbuffer_size = newsize
			Assert _colorbuffer Else "Unable to resize color buffer"
		EndIf
		
		MemCopy(_vertbuffer+(_index*12), points, elements*12)
		If texcoords Then
			MemCopy(_texcoordbuffer+(_index*8), texcoords, elements*8)
		EndIf
		If colors Then
			MemCopy(_colorbuffer+(_index*4), colors, elements*4)
		Else
			memset_(_colorbuffer+(_index*4), 255, elements*4)
		EndIf
		
		_sets :+ 1
		_indexTop.indices :+ 1
		
		_index :+ elements
		_indexTop.numIndices :+ elements
	End Method
	
	Method LockBuffers()
		If _lock = 0 And _index Then
			glVertexPointer(3, GL_FLOAT, 0, _vertbuffer)
			glColorPointer(4, GL_UNSIGNED_BYTE, 0, _colorbuffer)
			glTexCoordPointer(2, GL_FLOAT, 0, _texcoordbuffer)
			
			If GL_EXT_compiled_vertex_array Then
				glLockArraysEXT(0, _index)
			EndIf
		EndIf
		_lock :+ 1
	End Method
 
	Method UnlockBuffers()
		Assert _lock > 0 Else "Unmatched unlock for buffers"
		_lock :- 1
		If _lock = 0 And _index Then
			If GL_EXT_compiled_vertex_array Then
				glUnlockArraysEXT()
			EndIf
			
			glVertexPointer(4, GL_FLOAT, 0, Null)
			glColorPointer(4, GL_FLOAT, 0, Null)
			glTexCoordPointer(4, GL_FLOAT, 0, Null)
		EndIf
	End Method
 
	Method Render()
		If _sets = 0 Then Return
		
		LockBuffers ' because we don't want to be robbed
		
		Local indexPointer%Ptr, countPointer%Ptr
		Local indexEnum:TListEnum, stateEnum:TListEnum
		
		' there's probably a better way to do this.	 Like having another type that contains both the state and indices.	 Or something.
		indexEnum = _renderIndexStack.ObjectEnumerator()
		stateEnum = _renderStateStack.ObjectEnumerator()
		While indexEnum.HasNext() And stateEnum.HasNext()
			Local state:TRenderState = TRenderState(stateEnum.NextObject())
			Local index:TRenderIndices = TRenderIndices(indexEnum.NextObject())
			
			If index.indices = 0 Then
				Continue
			EndIf
			
			state.Bind()
			
			If GL_VERSION_1_4 Then
				If 1 < index.indices Then
					glMultiDrawArrays(state.renderMode, Varptr _arrindices[index.indexFrom], Varptr _arrcounts[index.indexFrom], index.indices)
				Else
					glDrawArrays(state.renderMode, _arrindices[index.indexFrom], _arrcounts[index.indexFrom])
				EndIf
			Else
				For Local i:Int = index.indexFrom Until index.indices
					glDrawArrays(state.renderMode, _arrindices[i], _arrcounts[i])
				Next
			EndIf
		Wend
		
		UnlockBuffers ' but sometimes we think we're safe
	End Method
 
	Method Reset()
		' make like nothing happened and equip a wig of charisma
		Assert _lock = 0 Else "Buffers are locked for rendering"
'		_vertstream.Seek(0)
'		_texcoordstream.Seek(0)
'		_colorstream.Seek(0)
		_index = 0
		_sets = 0
		
		_stateTop = _stateTop.Clone()
		_renderStateStack.Clear()
		_renderStateStack.AddLast(_stateTop)
		
		_indexTop = New TRenderIndices
		_renderIndexStack.Clear()
		_renderIndexStack.AddLast(_indexTop)
	End Method
End Type
EndRem
