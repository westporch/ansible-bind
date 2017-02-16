#!/bin/bash
# Hyun-gwan Seo

: ' 
이 스크립트는 ansible-master에서 실행해야 함

<start.sh 사용시 변경해야 할 변수 및 파일>
[배열] pm_arr: pm(Physical Machine)들의 ip 주소 목록
[변수] iteration: 반복 횟수
[변수] startup_vm: 시작할 vm 대수
[변수] fork: ansible에서 사용하는 fork 개수. 3 또는 6으로 설정해야 함. ansible 자체의 default fork는 5임
[파일] ansible에서 사용하는 hosts 파일을 수정해야 함
[배열] vm_arr: vm(Virtual Machine)들의 ip 주소 목록
'

: ' pm들의 IP 주소

 IP(private)   hostname
------------------------
192.168.24.1  uxen-pm01
192.168.24.3  uxen-pm03
192.168.24.6  uxen-pm06
'

pm_arr=("192.168.24.1" "192.168.24.3" "192.168.24.6")                   # pm(Physical Machine) 들의 IP 주소
#pm_arr=("192.168.24.3")                                                # pm(Physical Machine) IP 주소
pm_count=${#pm_arr[@]}                                                  # pm(Physical Machine) 개수

iteration=5                                                             # ansible playbook 실행 횟수
startup_vm=6                                                            # pm_arr에 있는 pm에서 실행할 전체 vm 개수
fork=3                                                                  # ansible playbook에서 fork할 개수 (3 또는 6으로 설정).

: ' vm들의 IP 주소

  IP(private)   hostname      os
-----------------------------------
192.168.24.211     vm1      centos
192.168.24.212     vm2      centos
192.168.24.213     vm3      centos
192.168.24.214     vm4      centos
192.168.24.215     vm5      centos
192.168.24.216     vm6      centos
'

vm_arr=("192.168.24.211" "192.168.24.212" "192.168.24.213" "192.168.24.214" "192.168.24.215" "192.168.24.216")
#vm_arr=("192.168.24.211")
vm_count=${#vm_arr[@]}                                                  # vm 개수
max_startup_vm=6                                                        # host에서 최대로 실행할 수 있는 vm 개수 (vm1~6)

#SSH="ssh -p31227"
ssh_pm="ssh -p31227"                                                    # pm에서는 ssh tcp/31227 포트를 사용함
ssh_vm="ssh"                                                            # ssh 기본 포트인 tcp/22를 사용함

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
            echo -e "===== `date` : Iteration$iter start, [pm=$pm_count, vm=$startup_vm, fork=$fork, real=(시간입력)] =====\n"  # 스크립트 실행 콘솔에 출력
            echo -e "===== `date` : Iteration$iter start, [pm=$pm_count, vm=$startup_vm, fork=$fork, real=(시간입력)] =====\n" >> $ansible_log

            # pm에서 초기화 스크립트 실행
            for((idx = 0; idx < $pm_count; idx++))
            do
                $ssh_pm ${pm_arr[$idx]} /data/bind_ansible/init.sh
                echo "${pm_arr[$idx]}에서 초기화 스크립트 실행 완료"
                echo -e "\n"
            done 
 
            # vm을 실행하는 for문
            for((num = 1; num <= $startup_vm; num++))                     
            do
                vm_idx=$num                                 # vm의 인덱스는 1부터 시작함 (vm의 이름은 vm1~6으로 부여됨)
                arr_idx=`expr $num - 1`                     # 배열에 선언된 인덱스는 0부터 시작함

                # 예외처리. 실행하고자 하는 vm 대수가 $pm_count(pm 대수)보다 클 경우 mod 연산을 해서 vm을 분산시킴
                if [ $arr_idx -qe $pm_count ]; then
                    arr_idx=`expr $arr_idx % $pm_count`
                fi

                # vm을 실행하는 명령
                $ssh_pm ${pm_arr[$arr_idx]} xl create /data/bind_ansible/vm${vm_idx}.cfg
            done
            
            # sleep 함수 실행 (시스템 부하 때문임)          
            go_to_sleep                                              

            : '
            # pm에서 dstat을 실행함
            for((idx = 0; idx < $pm_count; idx++))
            do       
                $ssh_pm ${pm_arr[$idx]} dstat $dstat_options /tmp/dstat.log_${pm_arr[$idx]}_iteration$iter.csv &   
            done
            '

            # vm_arr에 정의된 vm에서 dstat을 실행함
            for((idx = 0; idx < $vm_count; idx++))
            do
                $ssh_vm ${vm_arr[$idx]} dstat $dstat_options /tmp/dstat.log_${vm_arr[$idx]}_iteration$iter.csv &               
            done

            # ansible playbook을 실행함. playbook은 master vm에서 실행함
            play_ansible_playbook
            
            for((idx = 0; idx < $pm_count; idx++))
            do  
                : '
                # dstat 프로세스를 중지함
                $ssh_pm ${pm_arr[$idx]} $kill_dstat
                '

                # vm_arr에 정의된 vm에서 vm을 종료함
                $ssh_vm ${vm_arr[$idx]} $kill_dstat

                # pm에서 실행 중인 vm[1-6]이 있으면 종료함
                for(( vm_num = 1; vm_num <= $max_startup_vm; vm_num++ ))     
                do
                    $ssh_pm ${pm_arr[$idx]} xl destroy vm$vm_num 2> /dev/null        
                done
            done

         # xl destroy 명령을 전송한 후 vm이 종료될 때까지 기다림
         sleep 5 

        echo -e "===== `date` : Iteration$iter end =====\n"                  # 스크립트 실행 콘솔에 출력
        echo -e "===== `date` : Iteration$iter end =====\n" >> $ansible_log

    done
}

main
