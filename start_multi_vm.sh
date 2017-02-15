#!/bin/bash
# Hyun-gwan Seo

: ' 
<start.sh 사용시 변경해야 할 변수 및 파일>
[변수] pm_arr: pm(Physical Machine)들의 ip 주소 목록
[변수] iteration: 반복 횟수
[변수] startup_vm: 시작할 vm 대수
[변수] fork: ansible에서 사용하는 fork 개수. 3 또는 6으로 설정해야 함. ansible 자체의 default fork는 5임
[파일] ansible에서 사용하는 hosts 파일을 수정해야 함
'

pm_arr=("192.168.24.1" "192.168.24.3" "192.168.24.6")                   # pm(Physical Machine) 들의 IP 주소
#pm_arr=("192.168.24.3")                                                # pm(Physical Machine) IP 주소
pm_count=${#pm_arr[@]}                                                  # pm(Physical Machine) 개수

iteration=1                                                             # ansible playbook 실행 횟수
startup_vm=3                                                            # pm_arr에 있는 pm에서 실행할 전체 vm 개수
fork=3                                                                  # ansible playbook에서 fork할 개수 (3 또는 6으로 설정).

SSH="ssh -p31227"
max_startup_vm=6                                                        # host에서 최대로 실행할 수 있는 vm 개수

dstat_options="-cdngy --time --output"                                  # dstat 명령에서 사용할 옵션
kill_dstat="pkill -f dstat"                                             # dstat 프로세스를 죽임

ansible_home=/root/ansible
ansible_log=/var/log/ansible.log                                        # ansible 로그 파일 위치

function go_to_sleep()
{
    echo "going to sleep..."
    sleep 120
    echo "wake up!"
}

#ansible playbook을 실행함 (ansible-playbook에서 python2로 선언해야 동작함), (ansible의 hosts 파일을 수정해야 함)
function play_ansible_playbook()
{
    echo "time ansible-playbook -i hosts sites.yml -f $fork"    
    time /usr/bin/ansible-playbook -i $ansible_home/hosts $ansible_home/sites.yml -f $fork
    sleep 5
}

function main()
{
    for ((iter = 0; iter < $iteration; iter++))
        do
            echo -e "===== `date`: $iter 번째 반복 실행 시작 <node=$pm_count, vm=$startup_vm, fork=$fork, real=(시간입력)> =====\n"  # 스크립트 실행 콘솔에 출력
            echo -e "===== `date`: $iter 번째 반복 실행 시작 <node=$pm_count, vm=$startup_vm, fork=$fork, real=(시간입력)> =====\n" >> $ansible_log

            # 초기화 스크립트 실행
            for((idx = 0; idx < $pm_count; idx++))
            do
                $SSH ${pm_arr[$idx]} /data/bind_ansible/init.sh
                echo "${pm_arr[$idx]}에서 초기화 스크립트 실행 완료"
                echo -e "\n"
            done 
 
                # vm 실행
                for((num = 1; num <= $startup_vm; num++))                     
                do
                    vm_idx=$num      # vm의 인덱스는 1부터 시작함
                    arr_idx=$num-1   # 배열에 선언된 인덱스는 0부터 시작함
                    $SSH ${pm_arr[$arr_idx]} xl create /data/bind_ansible/vm${vm_idx}.cfg
                    #echo -e "\n\n`date` - host ${pm_arr[$arr_idx]}에서 vm${vm_idx} 실행 완료" >> $ansible_log
                done
            
            # sleep 함수 실행 (시스템 부하 때문임)          
            go_to_sleep                                              

            # dstat을 실행함
            for((idx = 0; idx < $pm_count; idx++))
            do       
                $SSH ${pm_arr[$idx]} dstat $dstat_options /tmp/dstat.log_${pm_arr[$idx]}_iteration$iter.csv &   
            done
            
            # ansible playbook을 실행함. playbook은 master vm에서 실행함
            play_ansible_playbook
            
            for((idx = 0; idx < $pm_count; idx++))
            do      
                # dstat 프로세스를 중지함
                $SSH ${pm_arr[$idx]} $kill_dstat

                # 실행 중인  vm[1-6]이 있으면 종료함
                for((vm_num = 1; vm_num <= $max_startup_vm; vm_num++ ))     
                do
                    $SSH ${pm_arr[$idx]} xl destroy vm$vm_num 2> /dev/null        
                done
            done

         # xl destroy 명령을 전송한 후 vm이 종료될 때까지 기다림
         sleep 5 
        
        echo -e "===== `date`: $iter 번째 반복 실행 종료 <node=$pm_count, vm=$startup_vm, fork=$fork, real=(시간입력)> =====\n"  # 스크립트 실행 콘솔에 출력
        echo -e "===== `date`: $iter 번째 반복 실행 종료 <node=$pm_count, vm=$startup_vm, fork=$fork, real=(시간입력)> =====\n" >> $ansible_log

    done
}

main
