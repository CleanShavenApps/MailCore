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

#import "CTBareAttachment.h"

#import "MailCoreUtilities.h"
#import "MailCoreTypes.h"
#import "CTMIME_SinglePart.h"
#import "CTCoreAttachment.h"

@implementation CTBareAttachment
@synthesize contentType=mContentType;
@synthesize contentId=mContentId;
@synthesize filename=mFilename;
@synthesize attachmentType = _attachmentType;
@synthesize size = _size;

- (id)initWithMIMESinglePart:(CTMIME_SinglePart *)part {
    self = [super init];
    if (self) {
        mMIMEPart = [part retain];
        self.filename = mMIMEPart.filename.length ? mMIMEPart.filename : mMIMEPart.name;		
        self.contentType = mMIMEPart.contentType;
		self.contentId = mMIMEPart.contentId;
		
		switch (mMIMEPart.disposition)
		{
			case CTContentDispositionTypeInline:
				_attachmentType = CTAttachmentTypeInline;
				break;
				
			case CTContentDispositionTypeAttachment:
			case CTContentDispositionTypeUndefined:
			default:
				_attachmentType = CTAttachmentTypeAttachment;
				break;
		}
		
		_size = mMIMEPart.size;
    }
    return self;
}

-(NSString*)decodedFilename {
	if (self.filename.length)
		return MailCoreDecodeMIMEPhrase((char *)[self.filename UTF8String]);
	
	return self.filename;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"Attachment: %@ (Content Type: %@, ID: %@, Disposition: %d, Size: %zd)",
                self.decodedFilename, self.contentType, self.contentId, (int) self.attachmentType, self.size];
}

- (CTCoreAttachment *)fetchFullAttachment {
    return [self fetchFullAttachmentWithProgress:^(size_t curr, size_t max) {}];
}

- (CTCoreAttachment *)fetchFullAttachmentWithProgress:(CTProgressBlock)block {
    [mMIMEPart fetchPartWithProgress:block];
    CTCoreAttachment *attach = [[CTCoreAttachment alloc] initWithData:mMIMEPart.data
                                                          contentType:self.contentType filename:self.filename];
    return [attach autorelease];
}

- (CTMIME_SinglePart *)part {
    return mMIMEPart;
}

- (void)dealloc {
    [mMIMEPart release];
    [mFilename release];
    [mContentType release];
	[mContentId release];
    [super dealloc];
}

@end
