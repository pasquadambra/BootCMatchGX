#ifndef _CUDAMACRO_H
#define _CUDAMACRO_H

#define MY_CUDA_CHECK( call) {                                    \
	    cudaError err = call;                                                    \
	    if( cudaSuccess != err) {                                                \
		            fprintf(stderr, "Cuda error in file '%s' in line %i : %s.\n",        \
					                    __FILE__, __LINE__, cudaGetErrorString( err) );              \
		            exit(EXIT_FAILURE);                                                  \
		        } }

#define MY_CHECK_ERROR(errorMessage) {                                    \
	    cudaError_t err = cudaGetLastError();                                    \
	    if( cudaSuccess != err) {                                                \
		            fprintf(stderr, "Cuda error: %s in file '%s' in line %i : %s, nthreads=%d, nblocks=%d, n=%d, number=%d.\n",    \
					                    errorMessage, __FILE__, __LINE__, cudaGetErrorString( err), nThreads, nBlocks, n, number );\
		            exit(EXIT_FAILURE);                                                  \
		        }                                                                        \
	    }

#define MY_CUBLAS_CHECK( call) {                                    \
            cublasStatus_t err = call;                                                    \
            if( CUBLAS_STATUS_SUCCESS != err) {                                                \
                            fprintf(stderr, "Cublas error in file '%s' in line %i : %d.\n",        \
                                                            __FILE__, __LINE__,  err);              \
                            exit(EXIT_FAILURE);                                                  \
                        } }
#define MY_CUSPARSE_CHECK( call) {                                    \
            cusparseStatus_t err = call;                                                    \
            if( CUSPARSE_STATUS_SUCCESS != err) {                                                \
                            fprintf(stderr, "Cusparse error in file '%s' in line %i : %d.\n",        \
                                                            __FILE__, __LINE__,  err);              \
                            exit(EXIT_FAILURE);                                                  \
                        } }



#endif

#ifdef USE_NVTX
#include "nvToolsExt.h"

const uint32_t colors[] = { 0xff00ff00, 0xff0000ff, 0xffffff00, 0xffff00ff, 0xff00ffff, 0xffff0000, 0xffffffff };
const int num_colors = sizeof(colors)/sizeof(uint32_t);

#define PUSH_RANGE(name,cid) { \
    int color_id = cid; \
    color_id = color_id%num_colors;\
    nvtxEventAttributes_t eventAttrib = {0}; \
    eventAttrib.version = NVTX_VERSION; \
    eventAttrib.size = NVTX_EVENT_ATTRIB_STRUCT_SIZE; \
    eventAttrib.colorType = NVTX_COLOR_ARGB; \
    eventAttrib.color = colors[color_id]; \
    eventAttrib.messageType = NVTX_MESSAGE_TYPE_ASCII; \
    eventAttrib.message.ascii = name; \
    nvtxRangePushEx(&eventAttrib); \
}
#define POP_RANGE nvtxRangePop();
#else
#define PUSH_RANGE(name,cid)
#define POP_RANGE
#endif

extern itype *iPtemp1;
extern vtype *vPtemp1;
extern itype *iAtemp1;
extern vtype *vAtemp1;
extern itype *idevtemp1;
extern itype *idevtemp2;
extern vtype *vdevtemp1;

