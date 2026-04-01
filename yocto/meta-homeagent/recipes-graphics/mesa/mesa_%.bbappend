# HomeAgent: RK3588S Mali-G610 GPU support
# meta-rockchip mesa bbappend에 rk3588s가 빠져있으므로 여기서 추가
# panfrost gallium이 panthor 커널 드라이버와 연동 (CSF 백엔드)
PACKAGECONFIG:append:rk3588s = " kmsro panfrost"
