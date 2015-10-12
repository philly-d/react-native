/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "RCTTextField.h"

#import "RCTConvert.h"
#import "RCTEventDispatcher.h"
#import "RCTUtils.h"
#import "UIView+React.h"
#import "RCTTextKeyValueConstants.h"

@implementation RCTTextField
{
  RCTEventDispatcher *_eventDispatcher;
  NSMutableArray *_reactSubviews;
  BOOL _jsRequestingFirstResponder;
  BOOL _textWasPasted;
  NSInteger _nativeEventCount;
  BOOL _submitted;
}

- (instancetype)initWithEventDispatcher:(RCTEventDispatcher *)eventDispatcher
{
  if ((self = [super initWithFrame:CGRectZero])) {
    RCTAssert(eventDispatcher, @"eventDispatcher is a required parameter");
    _eventDispatcher = eventDispatcher;
    [self addTarget:self action:@selector(textFieldDidChange) forControlEvents:UIControlEventEditingChanged];
    [self addTarget:self action:@selector(textFieldBeginEditing) forControlEvents:UIControlEventEditingDidBegin];
    [self addTarget:self action:@selector(textFieldEndEditing) forControlEvents:UIControlEventEditingDidEnd];
    [self addTarget:self action:@selector(textFieldSubmitEditing) forControlEvents:UIControlEventEditingDidEndOnExit];
    _reactSubviews = [NSMutableArray new];
  }
  return self;
}

RCT_NOT_IMPLEMENTED(- (instancetype)initWithFrame:(CGRect)frame)
RCT_NOT_IMPLEMENTED(- (instancetype)initWithCoder:(NSCoder *)aDecoder)

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
  
  // Only allow single keypresses for onKeyPress, pasted text will not be sent.
  if (_textWasPasted == NO) {
    [self sendKeyValueForString:string atRange:range];
  } else {
    _textWasPasted = NO;
  }
  
  if (_maxLength == nil || [string isEqualToString:RCTNewlineRawValue]) {  // Make sure forms can be submitted via return
    return YES;
  }
  NSUInteger allowedLength = _maxLength.integerValue - textField.text.length + range.length;
  if (string.length > allowedLength) {
    if (string.length > 1) {
      // Truncate the input string so the result is exactly maxLength
      NSString *limitedString = [string substringToIndex:allowedLength];
      NSMutableString *newString = textField.text.mutableCopy;
      [newString replaceCharactersInRange:range withString:limitedString];
      textField.text = newString;
      // Collapse selection at end of insert to match normal paste behavior
      UITextPosition *insertEnd = [textField positionFromPosition:textField.beginningOfDocument
                                                          offset:(range.location + allowedLength)];
      textField.selectedTextRange = [textField textRangeFromPosition:insertEnd toPosition:insertEnd];
      [self _textFieldDidChange];
    }
    return NO;
  } else {
    return YES;
  }
}

- (void)paste:(id)sender
{
  _textWasPasted = YES;
  [super paste:sender];
}

- (void)sendKeyValueForString:(NSString *)string atRange:(NSRange)range
{
  NSString *keyValue;
  
  if ([string isEqualToString:RCTNewlineRawValue]) {
    keyValue = RCTEnterKeyValue;
  } else if ([string isEqualToString:@""]) {
    keyValue = RCTBackspaceKeyValue;
  } else {
    keyValue = string;
  }
    
    NSDictionary *info = @{
                            @"keyValue": keyValue,
                            @"location": @(range.location),
                            @"length": @(range.length)
                        };
  
  [_eventDispatcher sendTextEventWithType:RCTTextEventTypeKeyPress
                                 reactTag:self.reactTag
                                     text:nil
                                      key:info
                               eventCount:_nativeEventCount];
}

/**
 * This method is a workaround since there is a bug in iOS 8.0 to 8.2 where the `deleteBackward` delegate
 * method was not being called. See: https://devforums.apple.com/message/1009150#1009150 < login required
 * The bug has since been resolved in iOS 8.3.
 */
- (BOOL)keyboardInputShouldDelete:(UITextField *)textField
{
  BOOL shouldDelete = YES;
  
  if ([UITextField instancesRespondToSelector:_cmd]) {
    BOOL (*keyboardInputShouldDelete)(id, SEL, UITextField *) = (BOOL (*)(id, SEL, UITextField *))[UITextField instanceMethodForSelector:_cmd];
    
    if (keyboardInputShouldDelete) {
      shouldDelete = keyboardInputShouldDelete(self, _cmd, textField);
    }
  }
  
  BOOL isIos8 = ([[[UIDevice currentDevice] systemVersion] intValue] == 8);
  BOOL isLessThanIos8_3 = ([[[UIDevice currentDevice] systemVersion] floatValue] < 8.3f);
  
  if (isIos8 && isLessThanIos8_3) {
    [self deleteBackward];
    return NO;
  }
  
  return shouldDelete;
}

// We use this `UIKeyInput` delegate method since `shouldChangeCharactersInRange` doesn't fire when
// there isn't any text in the UITextField. This fires no matter what.
- (void)deleteBackward
{
    
    UITextRange *range = self.selectedTextRange;
    NSInteger location = [self offsetFromPosition:self.beginningOfDocument toPosition:range.start];
    NSInteger length = [self offsetFromPosition:range.start toPosition:range.end];
    if (location == 0 && length == 0) {
        if ([self.delegate respondsToSelector:@selector(textField:shouldChangeCharactersInRange:replacementString:)]) {
            [self.delegate textField:self shouldChangeCharactersInRange:NSMakeRange(0, 0) replacementString:@""];
        }
    }
  [super deleteBackward];
}

- (void)setText:(NSString *)text
{
  NSInteger eventLag = _nativeEventCount - _mostRecentEventCount;
  if (eventLag == 0 && ![text isEqualToString:self.text]) {
    UITextRange *selection = self.selectedTextRange;
    super.text = text;
    self.selectedTextRange = selection; // maintain cursor position/selection - this is robust to out of bounds
  } else if (eventLag > RCTTextUpdateLagWarningThreshold) {
    RCTLogWarn(@"Native TextInput(%@) is %zd events ahead of JS - try to make your JS faster.", self.text, eventLag);
  }
}

static void RCTUpdatePlaceholder(RCTTextField *self)
{
  if (self.placeholder.length > 0 && self.placeholderTextColor) {
    self.attributedPlaceholder = [[NSAttributedString alloc] initWithString:self.placeholder
                                                                 attributes:@{
                                                                              NSForegroundColorAttributeName : self.placeholderTextColor
                                                                              }];
  } else if (self.placeholder.length) {
    self.attributedPlaceholder = [[NSAttributedString alloc] initWithString:self.placeholder];
  }
}

- (void)setPlaceholderTextColor:(UIColor *)placeholderTextColor
{
  _placeholderTextColor = placeholderTextColor;
  RCTUpdatePlaceholder(self);
}

- (void)setPlaceholder:(NSString *)placeholder
{
  super.placeholder = placeholder;
  RCTUpdatePlaceholder(self);
}

- (NSArray *)reactSubviews
{
  // TODO: do we support subviews of textfield in React?
  // In any case, we should have a better approach than manually
  // maintaining array in each view subclass like this
  return _reactSubviews;
}

- (void)removeReactSubview:(UIView *)subview
{
  // TODO: this is a bit broken - if the TextField inserts any of
  // its own views below or between React's, the indices won't match
  [_reactSubviews removeObject:subview];
  [subview removeFromSuperview];
}

- (void)insertReactSubview:(UIView *)view atIndex:(NSInteger)atIndex
{
  // TODO: this is a bit broken - if the TextField inserts any of
  // its own views below or between React's, the indices won't match
  [_reactSubviews insertObject:view atIndex:atIndex];
  [super insertSubview:view atIndex:atIndex];
}

- (CGRect)caretRectForPosition:(UITextPosition *)position
{
  if (_caretHidden) {
    return CGRectZero;
  }
  return [super caretRectForPosition:position];
}

- (CGRect)textRectForBounds:(CGRect)bounds
{
  CGRect rect = [super textRectForBounds:bounds];
  return UIEdgeInsetsInsetRect(rect, _contentInset);
}

- (CGRect)editingRectForBounds:(CGRect)bounds
{
  return [self textRectForBounds:bounds];
}

- (void)setAutoCorrect:(BOOL)autoCorrect
{
  self.autocorrectionType = (autoCorrect ? UITextAutocorrectionTypeYes : UITextAutocorrectionTypeNo);
}

- (BOOL)autoCorrect
{
  return self.autocorrectionType == UITextAutocorrectionTypeYes;
}

- (void)textFieldDidChange
{
  _nativeEventCount++;
  [_eventDispatcher sendTextEventWithType:RCTTextEventTypeChange
                                 reactTag:self.reactTag
                                     text:self.text
                                      key:nil
                               eventCount:_nativeEventCount];
}

- (void)textFieldEndEditing
{
  [_eventDispatcher sendTextEventWithType:RCTTextEventTypeEnd
                                 reactTag:self.reactTag
                                     text:self.text
                                      key:nil
                               eventCount:_nativeEventCount];
}
- (void)textFieldSubmitEditing
{
  _submitted = YES;
  [_eventDispatcher sendTextEventWithType:RCTTextEventTypeSubmit
                                 reactTag:self.reactTag
                                     text:self.text
                                      key:nil
                               eventCount:_nativeEventCount];
}

- (void)textFieldBeginEditing
{
  if (_selectTextOnFocus) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self selectAll:nil];
    });
  }
  [_eventDispatcher sendTextEventWithType:RCTTextEventTypeFocus
                                 reactTag:self.reactTag
                                     text:self.text
                                      key:nil
                               eventCount:_nativeEventCount];
}

- (BOOL)textFieldShouldEndEditing:(UITextField *)textField
{
  if (_submitted) {
    _submitted = NO;
    return _blurOnSubmit;
  }
  return YES;
}

- (BOOL)becomeFirstResponder
{
  _jsRequestingFirstResponder = YES;
  BOOL result = [super becomeFirstResponder];
  _jsRequestingFirstResponder = NO;
  return result;
}

- (BOOL)resignFirstResponder
{
  BOOL result = [super resignFirstResponder];
  if (result)
  {
    [_eventDispatcher sendTextEventWithType:RCTTextEventTypeBlur
                                   reactTag:self.reactTag
                                       text:self.text
                                        key:nil
                                 eventCount:_nativeEventCount];
  }
  return result;
}

- (BOOL)canBecomeFirstResponder
{
  return _jsRequestingFirstResponder;
}

@end
