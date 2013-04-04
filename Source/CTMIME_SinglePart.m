/*
 * MailCore
 *
 * Copyright (C) 2007 - Matt Ronge
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of the MailCore project nor the names of its
 *    contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHORS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHORS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#import "CTMIME_SinglePart.h"

#import <libetpan/libetpan.h>
#import "MailCoreTypes.h"
#import "MailCoreUtilities.h"


static inline struct imap_session_state_data *
get_session_data(mailmessage * msg)
{
    return msg->msg_session->sess_data;
}

static inline mailimap * get_imap_session(mailmessage * msg)
{
    return get_session_data(msg)->imap_session;
}

static void download_progress_callback(size_t current, size_t maximum, void * context) {
    CTProgressBlock block = context;
    block(current, maximum);
}

@interface CTMIME_SinglePart ()
@end

@implementation CTMIME_SinglePart
@synthesize attached=mAttached;
@synthesize filename=mFilename;
@synthesize contentId=mContentId;
@synthesize data=mData;
@synthesize fetched=mFetched;

+ (id)mimeSinglePartWithData:(NSData *)data {
    return [[[CTMIME_SinglePart alloc] initWithData:data] autorelease];
}

- (id)initWithData:(NSData *)data {
    self = [super init];
    if (self)
	{
        mData = [data retain];
        mFetched = YES;
		_disposition = CTContentDispositionTypeUndefined;
    }
    return self;
}

- (id)initWithMIMEStruct:(struct mailmime *)mime 
        forMessage:(struct mailmessage *)message {
    self = [super initWithMIMEStruct:mime forMessage:message];
    if (self)
	{
        mData = nil;
        mMime = mime;
        mMessage = message;
        mFetched = NO;
		_disposition = CTContentDispositionTypeUndefined;

        mMimeFields = mailmime_single_fields_new(mMime->mm_mime_fields, mMime->mm_content_type);
        if (mMimeFields != NULL)
		{	
			// .contentId if content-id if present
            if (mMimeFields->fld_id != NULL) {
                mContentId =
				[[NSString stringWithCString:mMimeFields->fld_id
									encoding:NSUTF8StringEncoding] retain];
            }
            
			// .disposition if content-disposition is present
			// .attached if content-disposition is attachment
            struct mailmime_disposition *disp = mMimeFields->fld_disposition;
            if (disp != NULL && disp->dsp_type != NULL)
			{
				mAttached =
				(disp->dsp_type->dsp_type == MAILMIME_DISPOSITION_TYPE_ATTACHMENT);
				
				switch (disp->dsp_type->dsp_type)
				{
					case MAILMIME_DISPOSITION_TYPE_INLINE:
						_disposition = CTContentDispositionTypeInline;
						break;
						
					case MAILMIME_DISPOSITION_TYPE_ATTACHMENT:
						_disposition = CTContentDispositionTypeAttachment;
						break;
						
					case MAILMIME_DISPOSITION_TYPE_ERROR:
					case MAILMIME_DISPOSITION_TYPE_EXTENSION:
					default:
						_disposition = CTContentDispositionTypeUndefined;
						break;
				}
			}
			
			// .filename if filename is present
            if (mMimeFields->fld_disposition_filename != NULL)
			{
                mFilename =
				[[NSString stringWithCString:mMimeFields->fld_disposition_filename
									encoding:NSUTF8StringEncoding] retain];
            }
			
			// .name if name is present
			if (mMimeFields->fld_content_name != NULL)
			{
				_name =
				[[NSString stringWithCString:mMimeFields->fld_content_name
									encoding:NSUTF8StringEncoding] retain];
			}
        }
    }
	
    return self;
}

- (BOOL)fetchPartWithProgress:(CTProgressBlock)block {
    if (self.fetched == NO) {
        struct mailmime_single_fields *mimeFields = NULL;

		BOOL mMimeIsNULL = mMime == NULL;
		BOOL mMimeFieldsIsNULL = (mMimeIsNULL || mMime->mm_mime_fields == NULL);
		BOOL mMimeContentTypeIsNULL = (mMimeIsNULL || mMime->mm_content_type == NULL);
		
		// DEBUG CODE TO TRACK CRASH
		if (mMimeFieldsIsNULL || mMimeFieldsIsNULL || mMimeContentTypeIsNULL)
		{
			NSAssert(0, @"mMime is NULL %d mm_mime_fields is NULL %d mm_content_type is NULL %d", mMimeIsNULL, mMimeFieldsIsNULL, mMimeContentTypeIsNULL);
		}
		
        int encoding = MAILMIME_MECHANISM_8BIT;
        mimeFields = mailmime_single_fields_new(mMime->mm_mime_fields, mMime->mm_content_type);
        if (mimeFields != NULL && mimeFields->fld_encoding != NULL)
            encoding = mimeFields->fld_encoding->enc_type;

        char *fetchedData = NULL;
        size_t fetchedDataLen;
        int r;

        if (mMessage->msg_session != NULL) {
            mailimap_set_progress_callback(get_imap_session(mMessage), &download_progress_callback, NULL, block);  
        }
        r = mailmessage_fetch_section(mMessage, mMime, &fetchedData, &fetchedDataLen);
        if (mMessage->msg_session != NULL) {
            mailimap_set_progress_callback(get_imap_session(mMessage), NULL, NULL, NULL); 
        }
        if (r != MAIL_NO_ERROR) {
            if (fetchedData) {
                mailmessage_fetch_result_free(mMessage, fetchedData);
            }
            self.lastError = MailCoreCreateErrorFromIMAPCode(r);
            return NO;
        }


        size_t current_index = 0;
        char * result;
        size_t result_len;
        r = mailmime_part_parse(fetchedData, fetchedDataLen, &current_index,
                                    encoding, &result, &result_len);
        if (r != MAILIMF_NO_ERROR) {
            mailmime_decoded_part_free(result);
            self.lastError = MailCoreCreateError(r, @"Error parsing the message");
            return NO;
        }
        NSData *data = [NSData dataWithBytes:result length:result_len];
        mailmessage_fetch_result_free(mMessage, fetchedData);
        mailmime_decoded_part_free(result);
        mailmime_single_fields_free(mimeFields);
        self.data = data;
        self.fetched = YES;
    }
    return YES;
}

- (BOOL)fetchPart {
    return [self fetchPartWithProgress:^(size_t curr, size_t max){}];
}

- (struct mailmime *)buildMIMEStruct {
    struct mailmime_fields *mime_fields;
    struct mailmime *mime_sub;
    struct mailmime_content *content;
    int r;

    if (mFilename) {
		char *charData = (char *)[mFilename cStringUsingEncoding:NSUTF8StringEncoding];
		char *dupeData = malloc(strlen(charData) + 1);
		strcpy(dupeData, charData);
		
		BOOL hasContentID = self.contentId.length > 2;
		
		// By default, an attachment unless self.disposition is inline or
		// we have content ID
		int disposition =
		(self.disposition == CTContentDispositionTypeInline || hasContentID) ?
		MAILMIME_DISPOSITION_TYPE_INLINE : MAILMIME_DISPOSITION_TYPE_ATTACHMENT;
		
		mime_fields =
		mailmime_fields_new_filename(disposition,
									 dupeData,
									 MAILMIME_MECHANISM_BASE64);

		// Add Content ID if present
		// Partially adapted from https://github.com/omolowa/MailCore.git
		if (hasContentID)
		{
			NSString *strippedContentID = [NSString stringWithString:self.contentId];
			
			// Strip the left < and right > if present
			if ([[strippedContentID substringToIndex:1] isEqualToString:@"<"])
				strippedContentID = [strippedContentID substringFromIndex:1];
			
			if ([[strippedContentID substringFromIndex:strippedContentID.length - 1] isEqualToString:@">"])
				strippedContentID = [strippedContentID substringToIndex:strippedContentID.length - 1];
			
			struct mailmime_field *mime_id = NULL;
			
            // These must be malloc-ated
            mime_id =
			mailmime_field_new(MAILMIME_FIELD_ID,
							   NULL,
							   NULL,
							   strdup((char *)[strippedContentID cStringUsingEncoding:NSUTF8StringEncoding]),
							   NULL,
							   1,
							   NULL,
							   NULL,
							   NULL);
			
            clist_append(mime_fields->fld_list, mime_id);
		}
		
    }
	
	else {
        mime_fields = mailmime_fields_new_encoding(MAILMIME_MECHANISM_BASE64);
    }
	
    content = mailmime_content_new_with_str([self.contentType cStringUsingEncoding:NSUTF8StringEncoding]);
    mime_sub = mailmime_new_empty(content, mime_fields);

    // Add Data
    r = mailmime_set_body_text(mime_sub, (char *)[self.data bytes], [self.data length]);
    return mime_sub;
}

- (size_t)size {
    if (mMime) {
        return mMime->mm_length;
    }
    return 0;
}

- (struct mailmime_single_fields *)mimeFields {
    return mMimeFields;
}

- (void)dealloc {
    mailmime_single_fields_free(mMimeFields);
    [mData release];
    [mFilename release];
	[_name release];
    [mContentId release];
    [_lastError release];
    //The structs are held by CTCoreMessage so we don't have to free them
    [super dealloc];
}
@end
