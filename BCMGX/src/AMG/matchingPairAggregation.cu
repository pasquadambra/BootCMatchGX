#include <cub/cub.cuh>

#include "matrix/matrixIO.h"

// Functor type for selecting values less than some criteria
struct Matched{
    int compare;
    __host__ __device__ __forceinline__
    Matched(int compare) : compare(compare) {}
    __host__ __device__ __forceinline__
    bool operator()(const int &a) const {
        return (a != compare);
    }
};

__global__
void _aggregate_symmetric_step_two(stype n, vtype *P_val, itype *M, itype *markc, vtype *w, itype *nuns, itype shift){

  itype i = blockDim.x * blockIdx.x + threadIdx.x;

  if ( i >= n ) {
      return;
  }
  if ( markc[i] != -1 ) {
      return;
  }

  // only single vertex and no-good pairs reach this point
  if( fabs(w[i]) > DBL_EPSILON ){ // good single
    int nuns_local = atomicAdd(nuns, 1);
    markc[i] = nuns_local;
    P_val[i] = w[i] / fabs(w[i]);
  }else{ // bad single
    markc[i] = (*nuns)-1;
    P_val[i] = 0.0;
  }
}

__global__
void _aggregate_symmetric_unsorted(stype n, vtype *P_val, itype *M, itype *markc, vtype *w, itype shift){

  itype i = blockDim.x * blockIdx.x + threadIdx.x;

  if(i >= n)
    return;

  itype v = i;
  itype u = M[i];

  // if it's a matched pair
  if(u != -1){

    vtype wv = w[v], wu = w[u];
    vtype normwagg = sqrt(wv * wv + wu * wu);

    if(normwagg > DBL_EPSILON){ // good pair
      // if v is the pair master
      if(v < u){
        markc[v] = v;
        markc[u] = -1;

        P_val[v] = wv / normwagg;
        P_val[u] = wu / normwagg;

        return;
      }
    }
  }
  markc[v] = -1;
}

__global__
void _aggregate_symmetric_sort(itype n, itype *P_col, const itype *__restrict__ M, const itype * __restrict__ comp_Pcol){
  itype i = blockDim.x * blockIdx.x + threadIdx.x;

  if(i >= n)
    return;

  itype v = comp_Pcol[i];
  itype u = M[v];
  P_col[v] = i;
  P_col[u] = i;
}

__global__
void _make_P_row(itype n, itype* P_row){

  itype v = blockDim.x * blockIdx.x + threadIdx.x;

  if(v > n){ return; }

  P_row[v] = v;
}

void  *d_temp_storage = NULL;

CSR* makeP_GPU(CSR *A, vector<itype> *M, vector<vtype> *w){

  CSR *P = CSRm::init(A->n, 1, A->n, true, true, false, A->full_n, A->row_shift);
  // recycle  allocated memory
  itype *comp_Pcol = P->row;

  Matched m(-1);
  scalar<itype> *d_num_selected_out = Scalar::init<itype>(0, true);

  gridblock gb = gb1d(A->n, BLOCKSIZE);
  _aggregate_symmetric_unsorted<<<gb.g, gb.b>>>(A->n, P->val, M->val, P->col, w->val, A->row_shift);

  // Determine temporary device storage requirements
  size_t   temp_storage_bytes = 0;

  cub::DeviceSelect::If(
    NULL,
    temp_storage_bytes,
    P->col,
    comp_Pcol,
    d_num_selected_out->val,
    M->n,
    m
  );

  // Allocate temporary storage
  if(d_temp_storage == NULL){
    CHECK_DEVICE( cudaMalloc(&d_temp_storage, temp_storage_bytes) );
  }

  cub::DeviceSelect::If(
    d_temp_storage,
    temp_storage_bytes,
    P->col,
    comp_Pcol,
    d_num_selected_out->val,
    M->n,
    m
  );

  itype *num_selected_out = Scalar::getvalueFromDevice(d_num_selected_out);
  gb = gb1d(*num_selected_out, BLOCKSIZE); 
  _aggregate_symmetric_sort<<<gb.g, gb.b>>>(*num_selected_out, P->col, M->val, comp_Pcol);

  gb = gb1d(A->n, BLOCKSIZE); 
  _aggregate_symmetric_step_two<<<gb.g, gb.b>>>(A->n, P->val, M->val, P->col, w->val, d_num_selected_out->val, A->row_shift);

  free(num_selected_out);
  num_selected_out = Scalar::getvalueFromDevice(d_num_selected_out);
  P->m = (*num_selected_out);

  gb = gb1d(A->n+1, BLOCKSIZE); 
  _make_P_row<<<gb.g, gb.b>>>(A->n, P->row);
  cudaDeviceSynchronize();
  free(num_selected_out);

  return P;
}

void matchingPairAggregation(handles *h, CSR *A, vector<vtype> *w, CSR **_P, CSR **_R){
  _MPI_ENV;

  vector<itype> *M = suitor(h, A, w);
  CSR *R, *P;

  // make P on GPU
  if(DETAILED_TIMING && ISMASTER) {
    cudaDeviceSynchronize();
    TIME::start();
  }	  
  P = makeP_GPU(A, M, w);
  if(DETAILED_TIMING && ISMASTER){
    cudaDeviceSynchronize();
    TOTAL_MAKE_P += TIME::stop();
  }

  itype m_shifts[nprocs];
  itype ms[nprocs];

  //get colum numbers other process
  if(nprocs > 1){
    // send columns numbers to each process
    CHECK_MPI(
      MPI_Allgather(
        &P->m,
        sizeof(itype),
        MPI_BYTE,
        &ms,
        sizeof(itype),
        MPI_BYTE,
        MPI_COMM_WORLD
      )
    );
    itype tot_m = 0;

    for(int i=0; i<nprocs; i++){
      m_shifts[i] = tot_m;
      tot_m += ms[i];
    }
    P->m = tot_m;
    CSRm::shift_cols(P, m_shifts[myid]);
    R = CSRm::T(h->cusparse_h0, P);
    R->row += m_shifts[myid];
    R->n = ms[myid];
    R->m = A->full_n;
    CSRm::shift_cols(R, P->row_shift);
    R->row_shift = m_shifts[myid];

  }else{
    R = CSRm::T(h->cusparse_h0, P);
  }

    free(M);

    *_P = P;
    *_R = R;
}
