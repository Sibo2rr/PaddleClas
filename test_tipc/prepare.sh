#!/bin/bash
FILENAME=$1

# MODE be one of ['lite_train_lite_infer' 'lite_train_whole_infer' 'whole_train_whole_infer',  
#                 'whole_infer', 'klquant_whole_infer',
#                 'cpp_infer', 'serving_infer',  'lite_infer']

MODE=$2

dataline=$(cat ${FILENAME})
# parser params
IFS=$'\n'
lines=(${dataline})

function func_parser_key(){
    strs=$1
    IFS=":"
    array=(${strs})
    tmp=${array[0]}
    echo ${tmp}
}

function func_parser_value(){
    strs=$1
    IFS=":"
    array=(${strs})
    if [ ${#array[*]} = 2 ]; then
        echo ${array[1]}
    else
    	IFS="|"
    	tmp="${array[1]}:${array[2]}"
        echo ${tmp}
    fi
}

model_name=$(func_parser_value "${lines[1]}")
model_url_value=$(func_parser_value "${lines[35]}")
model_url_key=$(func_parser_key "${lines[35]}")

if [[ $FILENAME == *GeneralRecognition* ]];then
   cd dataset
   rm -rf Aliproduct
   rm -rf train_reg_all_data.txt
   rm -rf demo_train
   wget -nc https://paddle-imagenet-models-name.bj.bcebos.com/data/whole_chain/tipc_shitu_demo_data.tar
   tar -xf tipc_shitu_demo_data.tar
   ln -s tipc_shitu_demo_data Aliproduct
   ln -s tipc_shitu_demo_data/demo_train.txt train_reg_all_data.txt
   ln -s tipc_shitu_demo_data/demo_train demo_train
   cd tipc_shitu_demo_data
   ln -s demo_test.txt val_list.txt
   cd ../../
   eval "wget -nc $model_url_value"
   mv general_PPLCNet_x2_5_pretrained_v1.0.pdparams GeneralRecognition_PPLCNet_x2_5_pretrained.pdparams
   exit 0
fi

if [ ${MODE} = "lite_train_lite_infer" ] || [ ${MODE} = "lite_train_whole_infer" ];then
    # pretrain lite train data
    cd dataset
    rm -rf ILSVRC2012
    wget -nc https://paddle-imagenet-models-name.bj.bcebos.com/data/whole_chain/whole_chain_little_train.tar
    tar xf whole_chain_little_train.tar
    ln -s whole_chain_little_train ILSVRC2012
    cd ILSVRC2012 
    mv train.txt train_list.txt
    mv val.txt val_list.txt
    if [ ${MODE} = "lite_train_lite_infer" ];then
	cp -r train/* val/
    fi
    cd ../../
elif [ ${MODE} = "whole_infer" ] || [ ${MODE} = "klquant_whole_infer" ];then
    # download data
    cd dataset
    rm -rf ILSVRC2012
    wget -nc https://paddle-imagenet-models-name.bj.bcebos.com/data/whole_chain/whole_chain_infer.tar
    tar xf whole_chain_infer.tar
    ln -s whole_chain_infer ILSVRC2012
    cd ILSVRC2012 
    mv val.txt val_list.txt
    ln -s val_list.txt train_list.txt
    cd ../../
    # download inference or pretrained model
    eval "wget -nc $model_url_value"
    if [[ $model_url_key == *inference* ]]; then
	rm -rf inference
	tar xf "${model_name}_inference.tar"
    fi
    if [[ $model_name == "SwinTransformer_large_patch4_window7_224" || $model_name == "SwinTransformer_large_patch4_window12_384" ]];then
	cmd="mv ${model_name}_22kto1k_pretrained.pdparams ${model_name}_pretrained.pdparams"
	eval $cmd
    fi

elif [ ${MODE} = "whole_train_whole_infer" ];then
    cd dataset
    rm -rf ILSVRC2012
    wget -nc https://paddle-imagenet-models-name.bj.bcebos.com/data/whole_chain/whole_chain_CIFAR100.tar
    tar xf whole_chain_CIFAR100.tar
    ln -s whole_chain_CIFAR100 ILSVRC2012
    cd ILSVRC2012 
    mv train.txt train_list.txt
    mv test.txt val_list.txt
    cd ../../
fi

if [ ${MODE} = "serving_infer" ];then
    # prepare serving env
    python_name=$(func_parser_value "${lines[2]}")
    ${python_name} -m pip install install paddle-serving-server-gpu==0.6.1.post101
    ${python_name} -m pip install paddle_serving_client==0.6.1
    ${python_name} -m pip install paddle-serving-app==0.6.1
    unset http_proxy
    unset https_proxy
    cd ./deploy/paddleserving
    wget -nc https://paddle-imagenet-models-name.bj.bcebos.com/dygraph/inference/ResNet50_vd_infer.tar && tar xf ResNet50_vd_infer.tar
fi

if [ ${MODE} = "cpp_infer" ];then
    cd deploy/cpp
    echo "################### build opencv ###################"
    rm -rf 3.4.7.tar.gz opencv-3.4.7/
    wget https://github.com/opencv/opencv/archive/3.4.7.tar.gz
    tar -xf 3.4.7.tar.gz
    install_path=$(pwd)/opencv-3.4.7/opencv3
    cd opencv-3.4.7/

    rm -rf build
    mkdir build
    cd build
    cmake .. \
	-DCMAKE_INSTALL_PREFIX=${install_path} \
	-DCMAKE_BUILD_TYPE=Release \
	-DBUILD_SHARED_LIBS=OFF \
	-DWITH_IPP=OFF \
	-DBUILD_IPP_IW=OFF \
	-DWITH_LAPACK=OFF \
	-DWITH_EIGEN=OFF \
	-DCMAKE_INSTALL_LIBDIR=lib64 \
	-DWITH_ZLIB=ON \
	-DBUILD_ZLIB=ON \
	-DWITH_JPEG=ON \
	-DBUILD_JPEG=ON \
	-DWITH_PNG=ON \
	-DBUILD_PNG=ON \
	-DWITH_TIFF=ON \
	-DBUILD_TIFF=ON
     make -j
     make install
     cd ../../
     echo "################### build opencv finished ###################"

     echo "################### build PaddleClas demo ####################"
     OPENCV_DIR=$(pwd)/opencv-3.4.7/opencv3/
     LIB_DIR=$(pwd)/Paddle/build/paddle_inference_install_dir/
     CUDA_LIB_DIR=$(dirname `find /usr -name libcudart.so`)
     CUDNN_LIB_DIR=$(dirname `find /usr -name libcudnn.so`)

     BUILD_DIR=build
     rm -rf ${BUILD_DIR}
     mkdir ${BUILD_DIR}
     cd ${BUILD_DIR}
     cmake .. \
        -DPADDLE_LIB=${LIB_DIR} \
        -DWITH_MKL=ON \
        -DDEMO_NAME=clas_system \
        -DWITH_GPU=OFF \
        -DWITH_STATIC_LIB=OFF \
        -DWITH_TENSORRT=OFF \
        -DTENSORRT_DIR=${TENSORRT_DIR} \
        -DOPENCV_DIR=${OPENCV_DIR} \
        -DCUDNN_LIB=${CUDNN_LIB_DIR} \
        -DCUDA_LIB=${CUDA_LIB_DIR} \

     make -j
     echo "################### build PaddleClas demo finished ###################"
fi
