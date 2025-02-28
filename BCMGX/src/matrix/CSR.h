#pragma once

#include <mpi.h>
#include <cusparse.h>


#include "vector.h"
#include "utility/setting.h"
#include "utility/utils.h"
#include "utility/myMPI.h"


struct halo_info{
  vector<itype> *to_receive;
  vector<itype> *to_receive_d;
  int to_receive_n;
  int *to_receive_counts;
  int *to_receive_spls;
  vtype *what_to_receive;
  vtype *what_to_receive_d;

  vector<itype> *to_send;
  vector<itype> *to_send_d;
  int to_send_n;
  int *to_send_counts;
  int *to_send_spls;
  vtype *what_to_send;
  vtype *what_to_send_d;
};


typedef struct rows_info{
  vector<itype> *nnz_per_row_shift;
  itype rows2bereceived;
  //itype total_row_to_rec;
  itype countall;
  itype *P_n_per_process;
  int *scounts;
  int *displr;
  int *displs;
  int *rcounts2;
  int *scounts2;
  int *displr2;
  int *displs2;
  unsigned int *rcvcntp;
  itype *rcvprow;
  itype *whichprow;
  itype *rcvpcolxrow;  
} rows_to_get_info;

#define PRINTM(x) CSRm::print(x, 0, 0); CSRm::print(x, 1, 0); CSRm::print(x, 2, 0);

typedef struct{
  stype nnz; // number of non-zero
  stype n; // rows number
  stype m; // columns number

  stype full_n;

  bool on_the_device;
  bool is_symmetric;

  vtype *val; // array of nnz values
  itype *col; // array of the column index
  itype *row; // array of the pointer of the first nnz element of the rows

  itype row_shift;

//  itype local_m;  // this variable should be removed

  // Matrix's cusparse descriptor
  cusparseMatDescr_t *descr;

  halo_info halo;
  
  rows_to_get_info *rows_to_get;
 
}CSR;


namespace CSRm{
  // NEW methods
  CSR** split(CSR *A, int nprocs);

  int choose_mini_warp_size(CSR *A);
  CSR* init(stype n, stype m, stype nnz, bool allocate_mem, bool on_the_device, bool is_symmetric, itype full_n, itype row_shift=0);
  void partialAlloc(CSR *A, bool init_row, bool init_col, bool init_val);
  void free(CSR *A);
  void free_rows_to_get(CSR *A);
  void freeStruct(CSR *A);
  void partialFree(CSR *A, bool val, bool col, bool row);
  void printInfo(CSR *A);
  void print(CSR *A, int type, int limit);
  bool equals(CSR *A, CSR *B);
  CSR* copyToDevice(CSR *A);
  CSR* copyToHost(CSR *A_d);
	CSR* clone(CSR *A);
  vtype vectorANorm(cublasHandle_t cublas_h, CSR *A, vector<vtype> *x);
  CSR* CSRCSR_product_cuSPARSE(cusparseHandle_t handle, CSR *A, CSR *B, bool transA=false, bool transB=false);
  vector<vtype>* diag(CSR *A);
  CSR *T(cusparseHandle_t cusparse_h, CSR* A);
  CSR* CSRCSR_product(cusparseHandle_t handle, CSR *A, CSR *B, bool transA=false, bool transB=false);
  vector<vtype>* CSRVector_product_adaptive_miniwarp(cusparseHandle_t cusparse_h, CSR *A, vector<vtype> *x, vector<vtype> *y, vtype alpha=1., vtype beta=0.);
  vector<vtype>* shifted_CSRVector_product_adaptive_miniwarp(CSR *A, vector<vtype> *x, vector<vtype> *y, itype shift, vtype alpha=1., vtype beta=0.);
  vector<vtype>* shifted_CSRVector_product_adaptive_miniwarp2(CSR *A, vector<vtype> *x, vector<vtype> *y, itype shift, vtype alpha=1., vtype beta=0.);

  vector<vtype>* CSRVector_product_CUSPARSE(cusparseHandle_t cusparse_h, CSR *A, vector<vtype> *x, vector<vtype> *y, bool trans=false, vtype alpha=1., vtype beta=0.);
  vector<vtype>* CSRVector_product_prolungator(CSR *A, vector<vtype> *x, vector<vtype> *y);
  vtype vectorANorm(cusparseHandle_t cusparse_h, cublasHandle_t cublas_h, CSR *A, vector<vtype> *x);
	vtype* toDense(cusparseHandle_t cusparse_h, CSR *A);
  void dismemberMatrix(cusparseHandle_t cusparse_h, CSR *A, CSR **U, CSR **L, vector<vtype> **D, cudaStream_t stream);
  vtype infinityNorm(CSR *A, cudaStream_t stream=DEFAULT_STREAM);
  void matrixVectorScaling(CSR *A, vector<vtype> *v, cudaStream_t stream=DEFAULT_STREAM);
  void iLU(cusparseHandle_t cusparse_h, CSR* A, bool trans);
  CSR* mergeDiagonal(CSR *A, vector<vtype> *D, cudaStream_t stream);
  vector<vtype>* absoluteRowSum(CSR *A, vector<vtype> *sum);
  void checkMatrix(CSR *A_, bool check_diagonal=false);
  void checkMatching(vector<itype> *v_);
  void checkColumnsOrder(CSR *A);
  bool equal(CSR *_A, CSR *_B);
  void shift_cols(CSR* A, itype shift);

  //kernels
  template <int OP_TYPE>
  __global__ void _CSR_vector_mul_mini_warp(itype n, int MINI_WARP_SIZE, vtype alpha, vtype beta, vtype *A_val, itype *A_row, itype *A_col, vtype *x, vtype *y);

}
