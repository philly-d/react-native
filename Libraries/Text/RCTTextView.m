/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "RCTTextView.h"

#import "RCTConvert.h"
#import "RCTEventDispatcher.h"
#import "RCTUtils.h"
#import "UIView+React.h"
#import "RCTTextKeyValueConstants.h"

@implementation RCTTextView
{
  RCTEventDispatcher *_eventDispatcher;
  BOOL _jsRequestingFirstResponder;
  NSString *_placeholder;
  UITextView *_placeholderView;
  UITextView *_textView;
  NSInteger _nativeEventCount;
}

- (instancetype)initWithEventDispatcher:(RCTEventDispatcher *)eventDispatcher
{
  RCTAssertParam(eventDispatcher);

  if ((self = [super initWithFrame:CGRectZero])) {
    _contentInset = UIEdgeInsetsZero;
    _eventDispatcher = eventDispatcher;
    _placeholderTextColor = [self defaultPlaceholderTextColor];

    _textView = [[UITextView alloc] initWithFrame:self.bounds];
    _textView.backgroundColor = [UIColor clearColor];
    _textView.delegate = self;
    [self addSubview:_textView];
  }
  return self;
}

RCT_NOT_IMPLEMENTED(-initWithFrame:(CGRect)frame)
RCT_NOT_IMPLEMENTED(-initWithCoder:(NSCoder *)aDecoder)

- (void)updateFrames
{
  // Adjust the insets so that they are as close as possible to single-line
  // RCTTextField defaults
  UIEdgeInsets adjustedInset = (UIEdgeInsets){
    _contentInset.top - 5, _contentInset.left - 4,
    _contentInset.bottom, _contentInset.right
  };

  [_textView setFrame:UIEdgeInsetsInsetRect(self.bounds, adjustedInset)];
  [_placeholderView setFrame:UIEdgeInsetsInsetRect(self.bounds, adjustedInset)];
}

- (void)updatePlaceholder
{
  [_placeholderView removeFromSuperview];
  _placeholderView = nil;

  if (_placeholder) {
    _placeholderView = [[UITextView alloc] initWithFrame:self.bounds];
    _placeholderView.backgroundColor = [UIColor clearColor];
    _placeholderView.scrollEnabled = false;
    _placeholderView.attributedText =
    [[NSAttributedString alloc] initWithString:_placeholder attributes:@{
      NSFontAttributeName : (_textView.font ? _textView.font : [self defaultPlaceholderFont]),
      NSForegroundColorAttributeName : _placeholderTextColor
    }];

    [self insertSubview:_placeholderView belowSubview:_textView];
    [self _setPlaceholderVisibility];
  }
}

- (UIFont *)font
{
  return _textView.font;
}

- (void)setFont:(UIFont *)font
{
  _textView.font = font;
  [self updatePlaceholder];
}

- (UIColor *)textColor
{
  return _textView.textColor;
}

- (void)setTextColor:(UIColor *)textColor
{
  _textView.textColor = textColor;
}

- (void)setPlaceholder:(NSString *)placeholder
{
  _placeholder = placeholder;
  [self updatePlaceholder];
}

- (void)setPlaceholderTextColor:(UIColor *)placeholderTextColor
{
  if (placeholderTextColor) {
    _placeholderTextColor = placeholderTextColor;
  } else {
    _placeholderTextColor = [self defaultPlaceholderTextColor];
  }
  [self updatePlaceholder];
}

- (void)setContentInset:(UIEdgeInsets)contentInset
{
  _contentInset = contentInset;
  [self updateFrames];
}

- (NSString *)text
{
  return _textView.text;
}

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{
  [self sendKeyValueForText:text];
  if (_maxLength == nil) {
    return YES;
  }
  NSUInteger allowedLength = _maxLength.integerValue - textView.text.length + range.length;
  if (text.length > allowedLength) {
    if (text.length > 1) {
      // Truncate the input string so the result is exactly maxLength
      NSString *limitedString = [text substringToIndex:allowedLength];
      NSMutableString *newString = textView.text.mutableCopy;
      [newString replaceCharactersInRange:range withString:limitedString];
      textView.text = newString;
      // Collapse selection at end of insert to match normal paste behavior
      UITextPosition *insertEnd = [textView positionFromPosition:textView.beginningOfDocument
                                                          offset:(range.location + allowedLength)];
      textView.selectedTextRange = [textView textRangeFromPosition:insertEnd toPosition:insertEnd];
      [self textViewDidChange:textView];
    }
    return NO;
  } else {
    return YES;
  }
}

- (void)sendKeyValueForText:(NSString *)text
{
  NSString *keyValue = kBackspaceKeyValue;
  
  BOOL keyNotBackspace = ![text isEqualToString:@""];
  
  if (keyNotBackspace) {
    keyValue = text;
    
    if ([text isEqualToString:@"\n"]) {
      keyValue = kEnterKeyValue;
    }
  }
  
  [_eventDispatcher sendTextEventWithType:RCTTextEventTypeKeyPress
                                 reactTag:self.reactTag
                                     text:keyValue
                               eventCount:_nativeEventCount];
}

- (void)setText:(NSString *)text
{
  NSInteger eventLag = _nativeEventCount - _mostRecentEventCount;
  if (eventLag == 0 && ![text isEqualToString:_textView.text]) {
    UITextRange *selection = _textView.selectedTextRange;
    [_textView setText:text];
    [self _setPlaceholderVisibility];
    _textView.selectedTextRange = selection; // maintain cursor position/selection - this is robust to out of bounds
  } else if (eventLag > RCTTextUpdateLagWarningThreshold) {
    RCTLogWarn(@"Native TextInput(%@) is %ld events ahead of JS - try to make your JS faster.", self.text, (long)eventLag);
  }
}

- (void)_setPlaceholderVisibility
{
  if (_textView.text.length > 0) {
    [_placeholderView setHidden:YES];
  } else {
    [_placeholderView setHidden:NO];
  }
}

- (void)setAutoCorrect:(BOOL)autoCorrect
{
  _textView.autocorrectionType = (autoCorrect ? UITextAutocorrectionTypeYes : UITextAutocorrectionTypeNo);
}

- (BOOL)autoCorrect
{
  return _textView.autocorrectionType == UITextAutocorrectionTypeYes;
}

- (BOOL)textViewShouldBeginEditing:(UITextView *)textView
{
  if (_selectTextOnFocus) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [textView selectAll:nil];
    });
  }
  return YES;
}

- (void)textViewDidBeginEditing:(UITextView *)textView
{
  if (_clearTextOnFocus) {
    _textView.text = @"";
    [self _setPlaceholderVisibility];
  }

  [_eventDispatcher sendTextEventWithType:RCTTextEventTypeFocus
                                 reactTag:self.reactTag
                                     text:textView.text
                               eventCount:_nativeEventCount];
}

- (void)textViewDidChange:(UITextView *)textView
{
  [self _setPlaceholderVisibility];
  _nativeEventCount++;
  [_eventDispatcher sendTextEventWithType:RCTTextEventTypeChange
                                 reactTag:self.reactTag
                                     text:textView.text
                               eventCount:_nativeEventCount];

}

- (void)textViewDidEndEditing:(UITextView *)textView
{
  [_eventDispatcher sendTextEventWithType:RCTTextEventTypeEnd
                                 reactTag:self.reactTag
                                     text:textView.text
                               eventCount:_nativeEventCount];
}

- (BOOL)becomeFirstResponder
{
  _jsRequestingFirstResponder = YES;
  BOOL result = [_textView becomeFirstResponder];
  _jsRequestingFirstResponder = NO;
  return result;
}

- (BOOL)resignFirstResponder
{
  [super resignFirstResponder];
  BOOL result = [_textView resignFirstResponder];
  if (result) {
    [_eventDispatcher sendTextEventWithType:RCTTextEventTypeBlur
                                   reactTag:self.reactTag
                                       text:_textView.text
                                 eventCount:_nativeEventCount];
  }
  return result;
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  [self updateFrames];
}

- (BOOL)canBecomeFirstResponder
{
  return _jsRequestingFirstResponder;
}

- (UIFont *)defaultPlaceholderFont
{
  return [UIFont systemFontOfSize:17];
}

- (UIColor *)defaultPlaceholderTextColor
{
  return [UIColor colorWithRed:0.0/255.0 green:0.0/255.0 blue:0.098/255.0 alpha:0.22];
}

@end
