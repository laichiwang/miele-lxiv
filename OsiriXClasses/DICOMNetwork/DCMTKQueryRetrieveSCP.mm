/*=========================================================================
  Program:   OsiriX

  Copyright (c) OsiriX Team
  All rights reserved.
  Distributed under GNU - LGPL
  
  See http://www.osirix-viewer.com/copyright.html for details.

     This software is distributed WITHOUT ANY WARRANTY; without even
     the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
     PURPOSE.
=========================================================================*/

/* See dcmqrscp.cc
 * See dcmtk/dcmnet/dcompat.h
 */

#undef verify
#include "dcmtk/config/osconfig.h"    /* make sure OS specific configuration is included first */

#import "DCMTKQueryRetrieveSCP.h"
#import "AppController.h"
#import "DICOMTLS.h"
#import "ContextCleaner.h"

//#include "dcmtk/dcmnet/dcompat.h"

#define INCLUDE_CSTDLIB
#define INCLUDE_CSTDIO
#define INCLUDE_CSTRING
#define INCLUDE_CSTDARG
#define INCLUDE_CERRNO
#define INCLUDE_CTIME
#define INCLUDE_LIBC
#include "dcmtk/ofstd/ofstdinc.h"

BEGIN_EXTERN_C
#ifdef HAVE_SYS_FILE_H
#include <sys/file.h>
#endif
#ifdef HAVE_SYS_TYPES_H
#include <sys/types.h>
#endif
#ifdef HAVE_SYS_WAIT_H
#include <sys/wait.h>
#endif
#ifdef HAVE_SYS_TIME_H
#include <sys/time.h>
#endif
#ifdef HAVE_SYS_RESOURCE_H
#include <sys/resource.h>
#endif
#ifdef HAVE_SYS_PARAM_H
#include <sys/param.h>
#endif
#ifdef HAVE_SYS_ERRNO_H
#include <sys/errno.h>
#endif
#ifdef HAVE_IO_H
#include <io.h>
#endif
#ifdef HAVE_PWD_H
#include <pwd.h>
#endif
#ifdef HAVE_GRP_H
#include <grp.h>
#endif
END_EXTERN_C

#include "dcmtk/dcmnet/dicom.h"
#include "dcmtk/dcmqrdb/dcmqropt.h"
#include "dcmtk/dcmnet/dimse.h"
#include "dcmtk/dcmqrdb/dcmqrcnf.h"
#include "dcmtk/dcmqrdb/dcmqrsrv.h"
#include "dcmtk/dcmdata/dcdict.h"
#include "dcmtk/dcmdata/cmdlnarg.h"
#include "dcmtk/ofstd/ofconapp.h"
#include "dcmtk/dcmdata/dcuid.h"       /* for dcmtk version name */

#ifdef WITH_SQL_DATABASE
#include "dcmtk/dcmqrdbx/dcmqrdbq.h"
#else
//#include "dcmtk/dcmqrdb/dcmqrdbi.h"
#include "dcmqrdbq.h" // glue/dcmqrdb
#endif

#include "DcmQueryRetrieveOsiriSCP.h"

#define OPENSSL_DISABLE_OLD_DES_SUPPORT // joris

#ifdef WITH_OPENSSL // joris
#ifdef UI
#undef UI // For MacOS 10.7 compilation
#endif
#include "dcmtk/dcmtls/tlstrans.h"
#include "dcmtk/dcmtls/tlslayer.h"
#endif

#ifdef WITH_ZLIB
#include <zlib.h>        /* for zlibVersion() */
#endif

#ifndef OFFIS_CONSOLE_APPLICATION
#define OFFIS_CONSOLE_APPLICATION "dcmqrscp"
#endif

static OFLogger dcmqrscpLogger = OFLog::getLogger("dcmtk.apps." OFFIS_CONSOLE_APPLICATION);

#define APPLICATIONTITLE    "DCMQRSCP"

extern OFLogger DCM_dcmnetLogger;

//const char *opt_configFileName = "dcmqrscp.cfg";
//OFBool      opt_checkFindIdentifier = OFFalse;
//OFBool      opt_checkMoveIdentifier = OFFalse;
//OFCmdUnsignedInt opt_port = 0;

DcmQueryRetrieveOsiriSCP *scp = nil;

OFCondition mainStoreSCP(T_ASC_Association * assoc,
                         T_DIMSE_C_StoreRQ * request,
                         T_ASC_PresentationContextID presId,
                         DcmQueryRetrieveDatabaseHandle *dbHandle)
{
	//OFBool isTLS = assoc->params->DULparams.useSecureLayer;
    
    if (scp)
        return scp->storeSCP( assoc, request, presId, *dbHandle, FALSE);
    
    NSLog( @"***** scp == nil !");
	return EC_IllegalCall;
}

@implementation DCMTKQueryRetrieveSCP

+ (BOOL) storeSCP
{
    if ([[NSUserDefaults standardUserDefaults] boolForKey: @"verbose_dcmtkStoreScu"])
    {
#ifndef NDEBUG
        OFLog::configure(OFLogger::DEBUG_LOG_LEVEL);
        //DCM_dcmdataLogger.setLogLevel(OFLogger::DEBUG_LOG_LEVEL);
        //DCM_dcmqrdbLogger.setLogLevel(OFLogger::DEBUG_LOG_LEVEL);
        //DCM_dcmnetLogger.setLogLevel(OFLogger::DEBUG_LOG_LEVEL);
#else
        OFLog::configure(OFLogger::INFO_LOG_LEVEL);
#endif
    }
    else
    {
        OFLog::configure(OFLogger::ERROR_LOG_LEVEL);
    }

	if( scp || [[NSUserDefaults standardUserDefaults] boolForKey:@"NinjaSTORESCP"]) // some undefined external entity is running a DICOM listener...
		return YES;
	else
		return NO;
}

- (BOOL) running
{
	return running;
}

- (int) port
{
	return _port;
}

- (NSString*) aeTitle
{
	return _aeTitle;
}

- (id)initWithPort:(int)port aeTitle:(NSString *)aeTitle  extraParameters:(NSDictionary *)params
{
	if (self = [super init]) {
		_port = port;
		_aeTitle = [aeTitle retain];
		_params = [params retain];
	}
    
#ifdef NONETWORKFUNCTIONS
    return nil;
#endif
    
	return self;
}

- (void)dealloc
{
	[_aeTitle release];
	[_params release];
	[super dealloc];
}

- (void)run
{
	OFCondition cond = EC_Normal;
    OFCmdUnsignedInt overrideMaxPDU = 0;
    DcmQueryRetrieveOptions options;
    
	//single process
	options.singleProcess_ = [[NSUserDefaults standardUserDefaults] boolForKey: @"SingleProcessMultiThreadedListener"];
	
	//debug
//	options.debug_ = OFTrue;
//	DUL_Debug(OFTrue);
//	DIMSE_debug(OFTrue);
//	SetDebugLevel(3);
	
	//no restrictions on moves
	options.restrictMoveToSameAE_ = OFFalse;
    options.restrictMoveToSameHost_ = OFFalse;
    options.restrictMoveToSameVendor_ = OFFalse;
	
	//only support Study Root for now
	options.supportPatientRoot_ = OFFalse;
	options.supportPatientStudyOnly_ = OFFalse;
	
	options.networkTransferSyntax_ = (E_TransferSyntax) [[NSUserDefaults standardUserDefaults] integerForKey: @"preferredSyntaxForIncoming"];
	
//	options.networkTransferSyntax_ = EXS_LittleEndianImplicit;		// See dcmqrsrv.mm
//	else options.networkTransferSyntax_ = EXS_LittleEndianExplicit;	// See dcmqrsrv.mm
	
	options.networkTransferSyntaxOut_ =  EXS_LittleEndianExplicit;	// EXS_JPEG2000		// See dcmqrcbm.mm - NOT USED
	/*
	options.networkTransferSyntaxOut_ = EXS_LittleEndianExplicit;
	options.networkTransferSyntaxOut_ = EXS_BigEndianExplicit;
	options.networkTransferSyntaxOut_ = EXS_JPEGProcess14SV1;
	options.networkTransferSyntaxOut_ = EXS_JPEGProcess1;
	options.networkTransferSyntaxOut_ = EXS_JPEGProcess2_4;
	options.networkTransferSyntaxOut_ = EXS_JPEG2000LosslessOnly;
	options.networkTransferSyntaxOut_ = EXS_JPEG2000;
	options.networkTransferSyntaxOut_ = EXS_RLELossless;
#ifdef WITH_ZLIB
	options.networkTransferSyntaxOut_ = EXS_DeflatedLittleEndianExplicit;
#endif
	options.networkTransferSyntaxOut_ = EXS_LittleEndianImplicit;
*/

	//timeout
	OFCmdSignedInt opt_timeout = [[NSUserDefaults standardUserDefaults] integerForKey:@"DICOMTimeout"];
    
    if( opt_timeout < 2)
        opt_timeout = 2;
    
    if( [[NSUserDefaults standardUserDefaults] integerForKey:@"DICOMConnectionTimeout"] > 0)
    {
        NSLog( @"--- DICOMConnectionTimeout: %d", (int) [[NSUserDefaults standardUserDefaults] integerForKey:@"DICOMConnectionTimeout"]);
        dcmConnectionTimeout.set( (Sint32) [[NSUserDefaults standardUserDefaults] integerForKey:@"DICOMConnectionTimeout"]);
    }
    else
        dcmConnectionTimeout.set( (Sint32) opt_timeout);
	
	//acse-timeout
	options.acse_timeout_ = OFstatic_cast(int, opt_timeout);
	
	//dimse-timeout
	options.dimse_timeout_ = OFstatic_cast(int, opt_timeout);
	options.blockMode_ = DIMSE_NONBLOCKING;
	
	//maxpdu
	//overrideMaxPDU = 
	
	//correct UID padding
	//options.correctUIDPadding_ = OFTrue
	
	//enble new VR
	dcmEnableUnknownVRGeneration.set(OFTrue);
	dcmEnableUnlimitedTextVRGeneration.set(OFTrue);
	
	//fix padding
	options.bitPreserving_ = OFFalse;
	
	//write metaheader
	options.useMetaheader_ = OFTrue;
	
	options.writeTransferSyntax_ = EXS_Unknown;
	
//	switch ( [[NSUserDefaults standardUserDefaults] integerForKey:@"ListenerCompressionSettings"]) //It's not a good idea, because it's a single process... no multi-threads
//	{
//		case 0:
//			options.writeTransferSyntax_ = EXS_Unknown;	//write with same syntax as it came in
//		break;
//			
//		case 1:
//			options.writeTransferSyntax_ = EXS_LittleEndianExplicit; //decompress
//		break;
//			
//		case 2:
//			options.writeTransferSyntax_ = EXS_JPEG2000;	// compress
//		break;
//	}
	
	//remove group lengths
	options.groupLength_ = EGL_withoutGL;
	
	//number of associations
	options.maxAssociations_ = 800;
	
	//port
//	opt_port = _port;
	
	//max PDU size
	options.maxPDU_ = ASC_DEFAULTMAXPDU;
	if (overrideMaxPDU > 0) options.maxPDU_ = overrideMaxPDU;	//;

    /* make sure data dictionary is loaded */
    if (!dcmDataDict.isDictionaryLoaded())
	{
#if 1 // original
		fprintf(stderr, "Warning: data dictionary not loaded, check environment variable: %s\n", DCM_DICT_ENVIRONMENT_VARIABLE);
        return;
#else
//        const char* env = NULL;
//        env = getenv(DCM_DICT_ENVIRONMENT_VARIABLE);
//        fprintf(stderr, "DCM_DICT_ENVIRONMENT_VARIABLE: %s\n", env);
        
        NSString *dicPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"/dicom.dic"];
        DcmDataDictionary& globalDataDict = dcmDataDict.wrlock();
        globalDataDict.clear();        // clear out any preloaded dictionary
        globalDataDict.loadDictionary([dicPath UTF8String], OFFalse);
        dcmDataDict.unlock();
        if (dcmDataDict.isDictionaryLoaded()) {
            fprintf(stderr, "Data dictionary loaded from resources\n");
        }
        else {
            fprintf(stderr, "Warning: data dictionary not loaded from resources\n");
            return;
        }
#endif
    }

	//init the network
	cond = ASC_initializeNetwork(NET_ACCEPTORREQUESTOR, (int)_port, options.acse_timeout_, &options.net_);
    if (cond.bad())
	{
        OFString temp_str;
        OFLOG_ERROR(dcmqrscpLogger, "Error initialising network:" << DimseCondition::dump(temp_str, cond));

        [[AppController sharedAppController] performSelectorOnMainThread:@selector(displayUpdateMessage:)
                                                              withObject:@"LISTENER"
                                                           waitUntilDone:NO];
		return;
    }
	
#if defined(HAVE_SETUID) && defined(HAVE_GETUID)
    /* return to normal uid so that we can't do too much damage in case
     * things go very wrong.   Only relevant if the program is setuid root,
     * and run by another user.  Running as root user may be
     * potentially disasterous if this program screws up badly.
     */
    setuid(getuid());
#endif
	
#ifdef WITH_OPENSSL // joris
	
	DcmTLSTransportLayer *tLayer = NULL;
	
	if([[_params objectForKey:@"TLSEnabled"] boolValue])
	{
		tLayer = new DcmTLSTransportLayer(DICOM_APPLICATION_ACCEPTOR, [TLS_SEED_FILE cStringUsingEncoding:NSUTF8StringEncoding]); // joris DICOM_APPLICATION_ACCEPTOR for server!!
		if (tLayer == NULL)
		{
			[[AppController sharedAppController] performSelectorOnMainThread:@selector(displayListenerError:)
                                                                  withObject:@"unable to create TLS transport layer"
                                                               waitUntilDone:NO];
			return;
		}
		
		TLSCertificateVerificationType certVerification = (TLSCertificateVerificationType)[[[NSUserDefaults standardUserDefaults] valueForKey:@"TLSStoreSCPCertificateVerification"] intValue];
		
		if(certVerification==VerifyPeerCertificate || certVerification==RequirePeerCertificate)
		{
			NSString *trustedCertificatesDir = [NSString stringWithFormat:@"%@%@", TLS_TRUSTED_CERTIFICATES_DIR, @"StoreSCPTLS"];
			[DDKeychain KeychainAccessExportTrustedCertificatesToDirectory:trustedCertificatesDir];
			NSArray *trustedCertificates = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:trustedCertificatesDir error:nil];
			
			for (NSString *cert in trustedCertificates)
			{
				if (TCS_ok != tLayer->addTrustedCertificateFile([[trustedCertificatesDir stringByAppendingPathComponent:cert] cStringUsingEncoding:NSUTF8StringEncoding], SSL_FILETYPE_PEM))
				{
					NSString *errMessage = [NSString stringWithFormat: @"DICOM Network Failure (storescp TLS) : Unable to load certificate file %@. You can turn OFF TLS Listener in Preferences->Listener.", [trustedCertificatesDir stringByAppendingPathComponent:cert]];
					[[AppController sharedAppController] performSelectorOnMainThread: @selector(displayListenerError:) withObject: errMessage waitUntilDone: NO];
					return;
				}
			}
			
//--add-cert-dir //// add certificates in d to list of certificates
//.... needs to use OpenSSL & rename files (see http://forum.dicom-cd.de/viewtopic.php?p=3237&sid=bd17bd76876a8fd9e7fdf841b90cf639 )

//			if (cmd.findOption("--add-cert-dir", 0, OFCommandLine::FOM_First))
//			{
//				const char *current = NULL;
//				do
//				{
//					app.checkValue(cmd.getValue(current));
//					if (TCS_ok != tLayer->addTrustedCertificateDir(current, opt_keyFileFormat))
//					{
//                      DCMQRDB_ERROR("warning unable to load certificates from directory '" << current << "', ignoring");

//					}
//				} while (cmd.findOption("--add-cert-dir", 0, OFCommandLine::FOM_Next));
//			}
		}
		
//		if (_dhparam && ! (tLayer->setTempDHParameters(_dhparam)))
//		{
//			localException = [NSException exceptionWithName:@"DICOM Network Failure (storescu TLS)" reason:[NSString stringWithFormat:@"Unable to load temporary DH parameter file %s", _dhparam] userInfo:nil];
//			[localException raise];
//		}
		
//		if (_doAuthenticate)
		{			
			tLayer->setPrivateKeyPasswd([[DICOMTLS TLS_PRIVATE_KEY_PASSWORD] cStringUsingEncoding:NSUTF8StringEncoding]);
			
			[DICOMTLS generateCertificateAndKeyForLabel:TLS_KEYCHAIN_IDENTITY_NAME_SERVER withStringID:@"StoreSCPTLS"]; // export certificate/key from the Keychain to the disk
			
			NSString *_privateKeyFile = [DICOMTLS keyPathForLabel:TLS_KEYCHAIN_IDENTITY_NAME_SERVER withStringID:@"StoreSCPTLS"]; // generates the PEM file for the private key
			NSString *_certificateFile = [DICOMTLS certificatePathForLabel:TLS_KEYCHAIN_IDENTITY_NAME_SERVER withStringID:@"StoreSCPTLS"]; // generates the PEM file for the certificate
			
			if (TCS_ok != tLayer->setPrivateKeyFile([_privateKeyFile cStringUsingEncoding:NSUTF8StringEncoding], SSL_FILETYPE_PEM))
			{
				NSString *errMessage = [NSString stringWithFormat: @"DICOM Network Failure (storescp TLS) : Unable to load private TLS key from %@. You can turn OFF TLS Listener in Preferences->Listener.", _privateKeyFile];
				[[AppController sharedAppController] performSelectorOnMainThread: @selector(displayListenerError:) withObject: errMessage waitUntilDone: NO];
				return;
			}
			
			if (TCS_ok != tLayer->setCertificateFile([_certificateFile cStringUsingEncoding:NSUTF8StringEncoding], SSL_FILETYPE_PEM))
			{
				NSString *errMessage = [NSString stringWithFormat: @"DICOM Network Failure (storescp TLS) : Unable to load certificate from %@. You can turn OFF TLS Listener in Preferences->Listener.", _certificateFile];
				[[AppController sharedAppController] performSelectorOnMainThread: @selector(displayListenerError:) withObject: errMessage waitUntilDone: NO];
				return;
			}
			
			if (!tLayer->checkPrivateKeyMatchesCertificate())
			{
				NSString *errMessage = [NSString stringWithFormat: @"DICOM Network Failure (storescp TLS) : Unable to load certificate from private key '%@' and certificate '%@' do not match. You can turn OFF TLS Listener in Preferences->Listener.", _privateKeyFile, _certificateFile];
				[[AppController sharedAppController] performSelectorOnMainThread: @selector(displayListenerError:) withObject: errMessage waitUntilDone: NO];
				return;
			}
		}
		
		NSArray *suites = [[NSUserDefaults standardUserDefaults] objectForKey:@"TLSStoreSCPCipherSuites"];
		NSMutableArray *selectedCipherSuites = [NSMutableArray array];
		
		for (NSDictionary *suite in suites)
		{
			if ([[suite objectForKey:@"Supported"] boolValue])
				[selectedCipherSuites addObject:[suite objectForKey:@"Cipher"]];
		}
		
		NSArray *_cipherSuites = [NSArray arrayWithArray:selectedCipherSuites];
		
		if(_cipherSuites)
		{
			const char *current = NULL;
			const char *currentOpenSSL;
			
			static OFString opt_ciphersuites(TLS1_TXT_RSA_WITH_AES_128_SHA ":" SSL3_TXT_RSA_DES_192_CBC3_SHA);
			opt_ciphersuites.clear();
			
			for (NSString *suite in _cipherSuites)
			{
				current = [suite cStringUsingEncoding:NSUTF8StringEncoding];
				
				if (NULL == (currentOpenSSL = DcmTLSTransportLayer::findOpenSSLCipherSuiteName(current)))
				{
					NSLog(@"ciphersuite '%s' is unknown.", current);
					NSLog(@"Known ciphersuites are:");
					
					unsigned long numSuites = DcmTLSTransportLayer::getNumberOfCipherSuites();
					for (unsigned long cs=0; cs < numSuites; cs++)
					{
						NSLog(@"%s", DcmTLSTransportLayer::getTLSCipherSuiteName(cs));
					}
					
					NSString *errMessage = [NSString stringWithFormat: @"DICOM Network Failure (storescp TLS) : Ciphersuite '%s' is unknown. You can turn OFF TLS Listener in Preferences->Listener.", current];
					[[AppController sharedAppController] performSelectorOnMainThread: @selector(displayListenerError:) withObject: errMessage waitUntilDone: NO];
					return;
				}
				else
				{
					if (opt_ciphersuites.length() > 0) opt_ciphersuites += ":";
					opt_ciphersuites += currentOpenSSL;
				}
				
			}
		
			if (TCS_ok != tLayer->setCipherSuites(opt_ciphersuites.c_str()))
			{
				NSString *errMessage = [NSString stringWithFormat: @"DICOM Network Failure (storescp TLS) : Unable to set selected cipher suites. You can turn OFF TLS Listener in Preferences->Listener."];
				[[AppController sharedAppController] performSelectorOnMainThread: @selector(displayListenerError:) withObject: errMessage waitUntilDone: NO];
				return;
			}
		}

		DcmCertificateVerification _certVerification;
		
		if(certVerification==RequirePeerCertificate)
			_certVerification = DCV_requireCertificate;
		else if(certVerification==VerifyPeerCertificate)
			_certVerification = DCV_checkCertificate;
		else
			_certVerification = DCV_ignoreCertificate;
		
		tLayer->setCertificateVerification(_certVerification);
		
		cond = ASC_setTransportLayer(options.net_, tLayer, 0);
		if (cond.bad())
		{
			DimseCondition::dump(cond);
			NSString *errMessage = [NSString stringWithFormat: @"DICOM Network Failure (storescp TLS) : ASC_setTransportLayer - %04x:%04x %s. You can turn OFF TLS Listener in Preferences->Listener.", cond.module(), cond.code(), cond.text()];
			[[AppController sharedAppController] performSelectorOnMainThread: @selector(displayListenerError:) withObject: errMessage waitUntilDone: NO];
			return;
		}
	}
#endif

// Have this to avoid errors until I can get rid of it
DcmQueryRetrieveConfig config;

//#ifdef WITH_SQL_DATABASE
    // use SQL database
    DcmQueryRetrieveOsiriXDatabaseHandleFactory factory;
//#else
    // use linear index database (index.dat)
//    DcmQueryRetrieveIndexDatabaseHandleFactory factory(&config);
//#endif
	 //use if static scp rather than pointer
    //DcmQueryRetrieveOsiriSCP scp(config, options, factory);
	//scp.setDatabaseFlags(OFFalse, OFFalse, options.debug_);

    DcmAssociationConfiguration asccfg;
    // TODO: init asccfg from configuration file

	DcmQueryRetrieveOsiriSCP *localSCP = new DcmQueryRetrieveOsiriSCP(config, options, factory, asccfg);
    scp = localSCP;
	
    localSCP->setDatabaseFlags(OFFalse, OFFalse);
    //localSCP->opt_secureConnection = [[_params objectForKey:@"TLSEnabled"] boolValue];

	_abort = NO;
	running = YES;
		
	// ********* WARNING -- NEVER NEVER CALL ANY COCOA (NSobject) functions after this point... fork() will be used ! fork is INCOMPATIBLE with NSObject ! See http://www.cocoadev.com/index.pl?ForkSafety
	// Even a simple NSLog() will cause many many problems......
	
    /* loop waiting for associations */
	if(cond.good())
	{
		while(!_abort)
		{
			@try
			{
				try
				{
					if( _abort == NO)
						cond = localSCP->waitForAssociation(options.net_);
				}
				catch(...)
				{
					NSLog( @"***** C++ exception in %s", __PRETTY_FUNCTION__);
				}
			}
			@catch (NSException * e)
			{
				NSLog( @"***** exception in %s: %@", __PRETTY_FUNCTION__, e);
			}
		}
	}
	
    [NSThread sleepForTimeInterval: 1];
    [ContextCleaner waitForHandledAssociations];
    [NSThread sleepForTimeInterval: 1];
    
	if( _abort)
		NSLog( @"---- store-SCP aborted");
    
	if( localSCP)
		delete localSCP;
	
	localSCP = NULL;
    scp = nil;
    
	if (cond.bad())
		OFLOG_ERROR(dcmqrscpLogger, "****** cond.good() != normal ---- DCMTKQueryRetrieve");
	
	cond = ASC_dropNetwork(&options.net_);
    if (cond.bad()) {
        OFString temp_str;
        OFLOG_ERROR(dcmqrscpLogger, "Error dropping network:" << DimseCondition::dump(temp_str, cond));
    }
	
	running = NO;
	
#ifdef WITH_OPENSSL // joris
	if( tLayer)
		delete tLayer;
#endif
	
    if([[_params objectForKey:@"TLSEnabled"] boolValue])
    {
        [[NSFileManager defaultManager] removeFileAtPath:[DICOMTLS keyPathForLabel:TLS_KEYCHAIN_IDENTITY_NAME_SERVER withStringID:@"StoreSCPTLS"] handler:nil];
        [[NSFileManager defaultManager] removeFileAtPath:[DICOMTLS certificatePathForLabel:TLS_KEYCHAIN_IDENTITY_NAME_SERVER withStringID:@"StoreSCPTLS"] handler:nil];
        [[NSFileManager defaultManager] removeFileAtPath:[NSString stringWithFormat:@"%@%@", TLS_TRUSTED_CERTIFICATES_DIR, @"StoreSCPTLS"] handler:nil];
    }
	return;
}

-(void)abort
{
	NSLog( @"---- store-SCP abort !");
	_abort = YES;
}

@end
