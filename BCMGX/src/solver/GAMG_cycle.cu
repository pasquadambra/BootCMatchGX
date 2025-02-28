#pragma once

#include "FCG.h"

#define RTOL 0.25

extern int DETAILED_TIMING;
float TOTAL_SOLRELAX_TIME=0.;
float TOTAL_RESTGAMG_TIME=0.;

namespace GAMGcycle{
  vector<vtype> *Res_buffer;

  void initContext(int n){
    GAMGcycle::Res_buffer = Vector::init<vtype>(n ,true, true);
  }

  __inline__
  void setBufferSize(itype n){
    GAMGcycle::Res_buffer->n = n;
  }

  void freeContext(){
    Vector::free(GAMGcycle::Res_buffer);
  }
}

void GAMG_cycle(handles *h, int k, bootBuildData *bootamg_data, boot *boot_amg, applyData *amg_cycle, vectorCollection<vtype> *Rhs, vectorCollection<vtype> *Xtent, int l){
  _MPI_ENV;

  hierarchy *hrrc = boot_amg->H_array[k];
  int relax_type = amg_cycle->relax_type;

  buildData *amg_data = bootamg_data->amg_data;
  int coarse_solver = amg_data->coarse_solver;

  if(VERBOSE > 0)
    std::cout << "GAMGCycle: start of level " << l << "\n";

  if(l == hrrc->num_levels){

	if(DETAILED_TIMING && ISMASTER){
     	TIME::start();
	}
#if LOCAL_COARSEST == 1
      relaxCoarsest(
        h,                                 
        amg_cycle->relaxnumber_coarse,      
        l-1,                                
        hrrc,                               
        Rhs->val[l-1],                      
        coarse_solver,                      
        amg_cycle->relax_weight,            
        Xtent->val[l-1],                    
        &FCG::context.Xtent_buffer_2->val[l-1],
        hrrc->A_array[l-1]->n
      );
#else
      relax(
        h,
        amg_cycle->relaxnumber_coarse,
        l-1,
        hrrc,
        Rhs->val[l-1], 
        coarse_solver,
        amg_cycle->relax_weight,
        Xtent->val[l-1], 
        &FCG::context.Xtent_buffer_2->val[l-1]
      );
#endif
      if(DETAILED_TIMING && ISMASTER){
      	TOTAL_SOLRELAX_TIME += TIME::stop();
      }
  }else{
    // presmoothing steps
    if(DETAILED_TIMING && ISMASTER){
     	TIME::start();
    }
    relax(
      h,
      amg_cycle->prerelax_number,
      l-1,
      hrrc,
      Rhs->val[l-1],
      relax_type,
      amg_cycle->relax_weight,
      Xtent->val[l-1],
      &FCG::context.Xtent_buffer_2->val[l-1]
    );
    if(DETAILED_TIMING && ISMASTER){
      	TOTAL_SOLRELAX_TIME += TIME::stop();
    }

    if(VERBOSE > 1){
      vtype tnrm = Vector::norm(h->cublas_h, Rhs->val[l-1]);
      std::cout << "RHS at level " << l << " " << tnrm << "\n";
      tnrm = Vector::norm(h->cublas_h, Xtent->val[l-1]);
      std::cout << "After first smoother at level " << l << " XTent " << tnrm << "\n";
    }

    // compute residual
if(DETAILED_TIMING && ISMASTER){
     	TIME::start();
}
    GAMGcycle::setBufferSize(Rhs->val[l-1]->n);
    vector<vtype> *Res = GAMGcycle::Res_buffer;
    Vector::copyTo(Res, Rhs->val[l-1]);

    // sync
    if(nprocs > 1)
      sync_solution(hrrc->A_array[l-1]->halo, hrrc->A_array[l-1], Xtent->val[l-1]);
    CSRm::CSRVector_product_adaptive_miniwarp(h->cusparse_h0, hrrc->A_array[l-1], Xtent->val[l-1], Res, -1., 1.);

    if(VERBOSE > 1){
      vtype tnrm = Vector::norm_MPI(h->cublas_h, Res);
      std::cout << "Residual at level " << l << " " << tnrm << "\n";
    }

    if(nprocs == 1){
      CSRm::CSRVector_product_adaptive_miniwarp(h->cusparse_h0, hrrc->R_array[l-1], Res, Rhs->val[l], 1., 0.);
    }else{
#if LOCAL_COARSEST == 1
    // before coarsets
    if(l == hrrc->num_levels-1){
      CSR *R = hrrc->R_array[l-1];
      vector<vtype> *Res_full = aggregateVector(Res, hrrc->A_array[l-1]->full_n);

      CSRm::CSRVector_product_adaptive_miniwarp(h->cusparse_h0, R, Res_full, Rhs->val[l], 1., 0.);
      Vector::free(Res_full);
    }else{

      CSR *R_local = hrrc->R_local_array[l-1];
      assert(hrrc->A_array[l-1]->full_n == R_local->m);

      vector<vtype> *Res_full = FCG::context.Xtent_buffer_2->val[l-1];
      cudaMemcpy(Res_full->val + hrrc->A_array[l-1]->row_shift, Res->val, hrrc->A_array[l-1]->n*sizeof(vtype), cudaMemcpyDeviceToDevice);

      CSRm::CSRVector_product_adaptive_miniwarp(h->cusparse_h0, R_local, Res_full, Rhs->val[l], 1., 0.);
    }
#else
      CSR *R_local = hrrc->R_local_array[l-1];
      vector<vtype> *Res_full = aggregateVector(Res, hrrc->A_array[l-1]->full_n, FCG::context.Xtent_buffer_2->val[l-1]);
      CSRm::CSRVector_product_adaptive_miniwarp(h->cusparse_h0, R_local, Res_full, Rhs->val[l], 1., 0.);
#endif

  }

   if(nprocs>1) {
        Vector::fillWithValueWithOff(Xtent->val[l], 0., boot_amg->H_array[k]->A_array[l]->n, boot_amg->H_array[k]->A_array[l]->row_shift);
   } else {
    Vector::fillWithValue(Xtent->val[l], 0.);
   }
if(DETAILED_TIMING && ISMASTER){
      	TOTAL_RESTGAMG_TIME += TIME::stop();
}

    for(int i=1; i<=amg_cycle->num_grid_sweeps[l-1]; i++){
      GAMG_cycle(h, k, bootamg_data, boot_amg, amg_cycle, Rhs, Xtent, l+1);
      if(l == hrrc->num_levels-1)
        break;
    }


if(DETAILED_TIMING && ISMASTER){
     	TIME::start();
}
    if(nprocs == 1)
      CSRm::CSRVector_product_adaptive_miniwarp(h->cusparse_h0, hrrc->P_array[l-1], Xtent->val[l], Xtent->val[l-1], 1., 1.);
    else
      CSRm::shifted_CSRVector_product_adaptive_miniwarp(hrrc->P_local_array[l-1], Xtent->val[l], Xtent->val[l-1], hrrc->P_local_array[l-1]->row_shift, 1., 1.);
if(DETAILED_TIMING && ISMASTER){
      	TOTAL_RESTGAMG_TIME += TIME::stop();
}


    if(VERBOSE > 1){
      vtype tnrm = Vector::norm(h->cublas_h, Xtent->val[l-1]);
      std::cout << "After recursion at level " << l << " XTent " << tnrm << "\n";
    }

    if(DETAILED_TIMING && ISMASTER){
     	TIME::start();
    }
    // postsmoothing steps
    relax(
      h,
      amg_cycle->postrelax_number,
      l-1,
      hrrc,
      Rhs->val[l-1],
      relax_type,
      amg_cycle->relax_weight,
      Xtent->val[l-1],
      &FCG::context.Xtent_buffer_2->val[l-1]
    );
    if(DETAILED_TIMING && ISMASTER){
      	TOTAL_SOLRELAX_TIME += TIME::stop();
    }


    if(VERBOSE > 1){
      vtype tnrm = Vector::norm(h->cublas_h, Xtent->val[l-1]);
      std::cout << "After second smoother at level " << l << " XTent " << tnrm << "\n";
    }

  }

  if(VERBOSE > 0)
      std::cout << "GAMGCycle: end of level " << l << "\n";
}

