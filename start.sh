#!/bin/bash

' :
<변경해야 할 변수>
host_arr
iteration
startup_vm
fork
'

#host_arr=("192.168.24.1" "192.168.24.3" "192.168.24.6")                # host(node) 들의 IP 주소
host_arr=("192.168.24.3")                                               # host(node) IP 주소
host_count=${#host_arr[@]}                                              # host(node) 개수

SSH="ssh -p31227"
iteration=1                                                             # ansible playbook 실행 횟수
startup_vm=1                                                            # host에서 실행할 vm 개수
max_startup_vm=6                                                        # host에서 최대로 실행할 수 있는 vm 개수

dstat_options="-cdngy --time --output"                                  # dstat 명령에서 사용할 옵션
kill_dstat="pkill -f dstat"                                                # dstat 프로세스를 죽임
ansible_home=/root/ansible
ansible_log=/var/log/ansible.log                                        # ansible 로그 파일 위치

fork=3                                                                  # ansible playbook에서 fork할 개수 (3 또는 6으로 설정). default fork 개수는 5

function go_to_sleep()
{
    echo "going to sleep..."
    sleep 120
    echo "wake up!"
}

function main()
{
    for ((iter = 0; iter < $iteration; iter++))
    do
                            
        for((idx = 0; idx < $host_count; idx++))
        do
            
            $SSH ${host_arr[$idx]} /data/bind_ansible/init.sh             # 초기화 스크립트 실행
          
            for((num = 1; num <= $startup_vm; num++))                     # VM 실행
            do
                $SSH ${host_arr[$idx]} xl create /data/bind_ansible/vm${num}.cfg
                echo -e "\n\n`date` - host ${host_arr[$idx]}에서 vm${num} 실행 완료" >> $ansible_log
            done
                
            go_to_sleep                                                   # sleep 함수 실행 (시스템 부하 때문임)
            
                
            # dstat을 실행함
            $SSH ${host_arr[$idx]} dstat $dstat_options /tmp/dstat.log_${host_arr[$idx]}_iteration$iter.csv &
                
            # $ansible_log에 $host_count, $startup_vm 등을 기록함 (time의 결과 값인 real은 수동으로 입력해야 함)
            echo "==== `date` <${host_arr[$idx]}-iteration$iter, node=$host_count, vm=$startup_vm, fork=$fork, real=(시간입력)> ====" >> $ansible_log
                
            #ansible playbook을 실행함 (ansible-playbook에서 python2로 선언해야 동작함), (hosts 파일을 수정해야 함)
            echo "time ansible-playbook -i hosts sites.yml -f $fork"    
            time /usr/bin/ansible-playbook -i $ansible_home/hosts $ansible_home/sites.yml -f $fork
            sleep 5
                
            # dstat 프로세스를 중지함
            $SSH ${host_arr[$idx]} $kill_dstat

            for((vm_num = 1; vm_num <= $max_startup_vm; vm_num++ ))     # 실행 중인  vm[1-6]이 있으면 종료함
            do
                $SSH ${host_arr[$idx]} xl destroy vm$vm_num 2> /dev/null        
            done
            
        done
        
    done
}

main
