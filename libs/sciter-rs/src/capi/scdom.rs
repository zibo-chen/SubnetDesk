//! DOM access methods, C interface.

#![allow(non_camel_case_types, non_snake_case)]

use capi::sctypes::*;

MAKE_HANDLE!(#[doc = "Element native handle."] HELEMENT, _HELEMENT);
MAKE_HANDLE!(#[doc = "Node native handle."] HNODE, _HNODE);

#[repr(C)]
#[derive(Debug, PartialOrd, PartialEq)]
/// Type of the result value for Sciter DOM functions.
pub enum SCDOM_RESULT {
	/// Function completed successfully.
	OK = 0,
	/// Invalid `HWINDOW`.
	INVALID_HWND = 1,
	/// Invalid `HELEMENT`.
	INVALID_HANDLE = 2,
	/// Attempt to use `HELEMENT` which is not attached to document.
	PASSIVE_HANDLE = 3,
	/// Parameter is invalid, e.g. pointer is null.
	INVALID_PARAMETER = 4,
	/// Operation failed, e.g. invalid html passed.
	OPERATION_FAILED = 5,
	/// Function completed successfully, but no result (e.g. no such attribute at element).
	OK_NOT_HANDLED = -1,
}

impl std::error::Error for SCDOM_RESULT {}

impl std::fmt::Display for SCDOM_RESULT {
	fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
		write!(f, "{:?}", self)
	}
}

#[repr(C)]
#[derive(Debug, PartialOrd, PartialEq)]
/// `dom::Element.set_html()` options.
pub enum SET_ELEMENT_HTML
{
	SIH_REPLACE_CONTENT     = 0,
	SIH_INSERT_AT_START     = 1,
	SIH_APPEND_AFTER_LAST   = 2,
	SOH_REPLACE             = 3,
	SOH_INSERT_BEFORE       = 4,
	SOH_INSERT_AFTER        = 5,
}

/// Bounding rectangle of the element.
#[repr(C)]
#[derive(Debug, PartialOrd, PartialEq)]
pub enum ELEMENT_AREAS {

	/// `or` this flag if you want to get Sciter window relative coordinates,
	/// otherwise it will use nearest windowed container e.g. popup window.
	ROOT_RELATIVE = 0x01,

	/// `or` this flag if you want to get coordinates relative to the origin of element iself.
	SELF_RELATIVE = 0x02,

	/// Position inside immediate container.
	CONTAINER_RELATIVE = 0x03,

	/// Position relative to view - Sciter window.
	VIEW_RELATIVE = 0x04,

	/// Content (inner)  box.
	CONTENT_BOX = 0x00,

	/// Content + paddings.
	PADDING_BOX = 0x10,

	/// Content + paddings + border.
	BORDER_BOX  = 0x20,

	/// Content + paddings + border + margins.
	MARGIN_BOX  = 0x30,

	/// Relative to content origin - location of background image (if it set `no-repeat`).
	BACK_IMAGE_AREA = 0x40,

	/// Relative to content origin - location of foreground image (if it set `no-repeat`).
	FORE_IMAGE_AREA = 0x50,

	/// Scroll_area - scrollable area in content box.
	SCROLLABLE_AREA = 0x60,
}

impl ELEMENT_AREAS {
	/// Size of content (i.e `(0, 0, width, height)`).
	pub fn self_content() -> u32 {
		ELEMENT_AREAS::SELF_RELATIVE as u32
	}

	/// Size of rect (i.e `(left, top, width, height)`)
	pub fn self_rect() -> u32 {
		ELEMENT_AREAS::ROOT_RELATIVE as u32
	}
}

/// Collection of states (runtime flags) of a DOM element.
///
/// They reflect CSS pseudo-classes that are used in selectors,
/// e.g. `STATE_HOVER` is `:hover`, `STATE_ACTIVE` is `:active`, and so on.
///
/// Implements `|` and `&` bitwise operators.
#[repr(transparent)]
#[derive(Debug, Copy, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub struct ELEMENT_STATE_BITS(pub UINT);

impl ELEMENT_STATE_BITS {

	/// Zero state.
    pub const STATE_NONE: Self = Self(0x00000000);
	/// Element is a link.
	///
	/// E.g. `<a href`.
    pub const STATE_LINK: Self = Self(0x00000001);
	/// Mouse over the element at the moment.
    pub const STATE_HOVER: Self = Self(0x00000002);
	/// Element is pressed.
	///
	/// Commonly used by `<button>` or `<a>` elements.
    pub const STATE_ACTIVE: Self = Self(0x00000004);
	/// Element is focused.
    pub const STATE_FOCUS: Self = Self(0x00000008);
	/// Element was visited.
	///
	/// For example, a link that was clicked.
    pub const STATE_VISITED: Self = Self(0x00000010);
	/// Current (hot) item.
    pub const STATE_CURRENT: Self = Self(0x00000020);
	/// Element is checked (or selected).
    pub const STATE_CHECKED: Self = Self(0x00000040);
	/// Element is disabled.
    pub const STATE_DISABLED: Self = Self(0x00000080);
	/// Readonly input element.
    pub const STATE_READONLY: Self = Self(0x00000100);
	/// Expanded state - e.g. nodes in tree view.
	///
	/// Mutually exclusive with `STATE_COLLAPSED`.
    pub const STATE_EXPANDED: Self = Self(0x00000200);
	/// Collapsed state - e.g. nodes in tree view.
	///
	/// Mutually exclusive with `STATE_EXPANDED`.
    pub const STATE_COLLAPSED: Self = Self(0x00000400);
	/// One of fore/back images was requested but is not delivered.
    pub const STATE_INCOMPLETE: Self = Self(0x00000800);
	/// Is animating currently.
    pub const STATE_ANIMATING: Self = Self(0x00001000);
	/// Will accept focus.
    pub const STATE_FOCUSABLE: Self = Self(0x00002000);
	/// Anchor in selection (used with current in selects).
    pub const STATE_ANCHOR: Self = Self(0x00004000);
	/// This is a synthetic element - i.e. don't emit it's head/tail.
    pub const STATE_SYNTHETIC: Self = Self(0x00008000);
	/// A popup element is shown for this particular element.
    pub const STATE_OWNS_POPUP: Self = Self(0x00010000);
	/// Focus gained by tab traversal.
    pub const STATE_TABFOCUS: Self = Self(0x00020000);
	/// Element is empty.
	///
	/// i.e. the element has no text content nor children nodes.
	///
	/// If element has a behavior attached then the behavior is responsible for the value of this flag.
    pub const STATE_EMPTY: Self = Self(0x00040000);
	/// Busy or loading.
    pub const STATE_BUSY: Self = Self(0x00080000);
	/// Drag over the block that can accept it (so is a current drop target).
	///
	/// Flag is set for the drop target block.
    pub const STATE_DRAG_OVER: Self = Self(0x00100000);
	/// Active drop target.
    pub const STATE_DROP_TARGET: Self = Self(0x00200000);
	/// Dragging/moving - the flag is set for the moving block.
    pub const STATE_MOVING: Self = Self(0x00400000);
	/// Dragging/copying - the flag is set for the copying block.
    pub const STATE_COPYING: Self = Self(0x00800000);
	/// Element that is a drag source.
    pub const STATE_DRAG_SOURCE: Self = Self(0x01000000);
	/// Element is drop marker.
    pub const STATE_DROP_MARKER: Self = Self(0x02000000);
	/// Close to `STATE_ACTIVE` but has wider life span.
	///
	/// E.g. in `MOUSE_UP` it is still on;
	/// so behavior can check it in `MOUSE_UP` to discover the `CLICK` condition.
    pub const STATE_PRESSED: Self = Self(0x04000000);
	/// This element is out of flow.
    pub const STATE_POPUP: Self = Self(0x08000000);
	/// The element or one of its containers has `dir=ltr` declared.
    pub const STATE_IS_LTR: Self = Self(0x10000000);
	/// The element or one of its containers has `dir=rtl` declared.
    pub const STATE_IS_RTL: Self = Self(0x20000000);
	/// Element is ready (behavior has finished initialization).
    pub const STATE_READY: Self = Self(0x40000000);
}

/// Flags can be OR'ed.
impl ::std::ops::BitOr for ELEMENT_STATE_BITS {
  type Output = ELEMENT_STATE_BITS;
  fn bitor(self, rhs: Self::Output) -> Self::Output {
    Self(self.0 | rhs.0)
  }
}

/// Flags can be AND'ed.
impl ::std::ops::BitAnd for ELEMENT_STATE_BITS {
  type Output = ELEMENT_STATE_BITS;
  fn bitand(self, rhs: Self::Output) -> Self::Output {
    Self(self.0 & rhs.0)
  }
}

pub type SciterElementCallback = extern "system" fn (he: HELEMENT, param: LPVOID) -> BOOL;

pub type ELEMENT_COMPARATOR = extern "system" fn (he1: HELEMENT, he2: HELEMENT, param: LPVOID) -> INT;
