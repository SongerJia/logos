-- ============================================================================
-- FlowPulse 流程脉冲智能业务平台 V1.0 - 数据库初始化脚本
-- ============================================================================
-- 数据库: MySQL 8.0+
-- 字符集: utf8mb4
-- 排序规则: utf8mb4_general_ci
-- 作者: FlowPulse架构组
-- 日期: 2026-06-10
-- 说明: 共17张核心表，覆盖7大领域（认证授权/工作流引擎/任务调度/
--       消息通知/系统日志/字典管理/文件存储）
-- ============================================================================

CREATE DATABASE IF NOT EXISTS `flowpulse` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
USE `flowpulse`;

-- ============================================================================
-- 第一部分：认证授权域（5张表）— RBAC 权限模型 + JWT Token 管理
-- ============================================================================

-- -----------------------------------------------------------
-- 1. sys_user 用户表
-- -----------------------------------------------------------
DROP TABLE IF EXISTS `sys_user`;
CREATE TABLE `sys_user` (
    `id`              BIGINT          NOT NULL AUTO_INCREMENT COMMENT '主键ID',
    `username`        VARCHAR(50)     NOT NULL                COMMENT '登录账号',
    `password`        VARCHAR(100)    NOT NULL                COMMENT 'BCrypt加密密码',
    `nickname`        VARCHAR(50)     DEFAULT NULL            COMMENT '用户昵称',
    `avatar`          VARCHAR(255)    DEFAULT NULL            COMMENT '头像URL',
    `email`           VARCHAR(100)    DEFAULT NULL            COMMENT '邮箱',
    `phone`           VARCHAR(20)     DEFAULT NULL            COMMENT '手机号',
    `gender`          TINYINT         DEFAULT 0               COMMENT '性别: 0未知 1男 2女',
    `status`          TINYINT         NOT NULL DEFAULT 1      COMMENT '状态: 0禁用 1正常',
    `dept_id`         BIGINT          DEFAULT NULL            COMMENT '部门ID',
    `last_login_ip`   VARCHAR(50)     DEFAULT NULL            COMMENT '最后登录IP',
    `login_time`      DATETIME        DEFAULT NULL            COMMENT '最后登录时间',
    `password_error_count` INT        NOT NULL DEFAULT 0      COMMENT '密码错误次数(连续失败锁定)',
    `lock_time`       DATETIME        DEFAULT NULL            COMMENT '锁定时间',
    `remark`          VARCHAR(500)    DEFAULT NULL            COMMENT '备注',
    `create_by`       BIGINT          DEFAULT NULL            COMMENT '创建人',
    `create_time`     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_by`       BIGINT          DEFAULT NULL            COMMENT '更新人',
    `update_time`     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `deleted`         TINYINT         NOT NULL DEFAULT 0      COMMENT '逻辑删除: 0未删 1已删除',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_username` (`username`),
    KEY `idx_phone` (`phone`),
    KEY `idx_email` (`email`),
    KEY `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='系统用户表';

-- -----------------------------------------------------------
-- 2. sys_role 角色表
-- -----------------------------------------------------------
DROP TABLE IF EXISTS `sys_role`;
CREATE TABLE `sys_role` (
    `id`              BIGINT          NOT NULL AUTO_INCREMENT COMMENT '主键ID',
    `role_name`       VARCHAR(50)     NOT NULL                COMMENT '角色名称',
    `role_code`       VARCHAR(50)     NOT NULL                COMMENT '角色编码',
    `parent_id`       BIGINT          DEFAULT 0               COMMENT '父角色ID(支持角色继承)',
    `sort_order`      INT             DEFAULT 0               COMMENT '排序',
    `status`          TINYINT         NOT NULL DEFAULT 1      COMMENT '状态: 0禁用 1正常',
    `data_scope`      CHAR(1)         DEFAULT '1'             COMMENT '数据权限范围: 1全部 2自定义 3本部门 4本部门及以下 5仅本人',
    `remark`          VARCHAR(500)    DEFAULT NULL            COMMENT '备注',
    `create_by`       BIGINT          DEFAULT NULL            COMMENT '创建人',
    `create_time`     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_by`       BIGINT          DEFAULT NULL            COMMENT '更新人',
    `update_time`     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `deleted`         TINYINT         NOT NULL DEFAULT 0      COMMENT '逻辑删除: 0未删 1已删除',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_role_code` (`role_code`),
    KEY `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='系统角色表';

-- -----------------------------------------------------------
-- 3. sys_permission 菜单权限表
-- -----------------------------------------------------------
DROP TABLE IF EXISTS `sys_permission`;
CREATE TABLE `sys_permission` (
    `id`              BIGINT          NOT NULL AUTO_INCREMENT COMMENT '主键ID',
    `permission_name` VARCHAR(50)     NOT NULL                COMMENT '菜单/权限名称',
    `permission_code` VARCHAR(100)    NOT NULL                COMMENT '权限标识(如 user:create)',
    `parent_id`       BIGINT          DEFAULT 0               COMMENT '父菜单ID(0为顶级)',
    `menu_type`       CHAR(1)         NOT NULL DEFAULT 'M'    COMMENT '类型: M目录 C菜单 F按钮',
    `path`            VARCHAR(200)    DEFAULT NULL            COMMENT '路由路径',
    `component`       VARCHAR(255)    DEFAULT NULL            COMMENT '组件路径',
    `icon`            VARCHAR(100)    DEFAULT NULL            COMMENT '图标',
    `sort_order`      INT             DEFAULT 0               COMMENT '排序',
    `visible`         CHAR(1)         DEFAULT '0'             COMMENT '是否显示: 0显示 1隐藏',
    `status`          TINYINT         NOT NULL DEFAULT 1      COMMENT '状态: 0禁用 1正常',
    `perms`           VARCHAR(100)    DEFAULT NULL            COMMENT '按钮权限标识',
    `remark`          VARCHAR(500)    DEFAULT NULL            COMMENT '备注',
    `create_time`     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time`     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `deleted`         TINYINT         NOT NULL DEFAULT 0      COMMENT '逻辑删除: 0未删 1已删除',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_permission_code` (`permission_code`),
    KEY `idx_parent_id` (`parent_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='菜单权限表';

-- -----------------------------------------------------------
-- 4. sys_user_role 用户-角色关联表
-- -----------------------------------------------------------
DROP TABLE IF EXISTS `sys_user_role`;
CREATE TABLE `sys_user_role` (
    `id`              BIGINT          NOT NULL AUTO_INCREMENT COMMENT '主键ID',
    `user_id`         BIGINT          NOT NULL                COMMENT '用户ID',
    `role_id`         BIGINT          NOT NULL                COMMENT '角色ID',
    `create_time`     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_user_role` (`user_id`, `role_id`),
    KEY `idx_role_id` (`role_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='用户角色关联表';

-- -----------------------------------------------------------
-- 5. sys_role_permission 角色-权限关联表
-- -----------------------------------------------------------
DROP TABLE IF EXISTS `sys_role_permission`;
CREATE TABLE `sys_role_permission` (
    `id`              BIGINT          NOT NULL AUTO_INCREMENT COMMENT '主键ID',
    `role_id`         BIGINT          NOT NULL                COMMENT '角色ID',
    `permission_id`   BIGINT          NOT NULL                COMMENT '权限ID',
    `create_time`     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_role_perm` (`role_id`, `permission_id`),
    KEY `idx_permission_id` (`permission_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='角色权限关联表';


-- ============================================================================
-- 第二部分：工作流引擎域（5张表）— 自研轻量级流程引擎核心 ★ 核心创新
-- ============================================================================

-- -----------------------------------------------------------
-- 6. wf_process_definition 流程定义表
-- -----------------------------------------------------------
DROP TABLE IF EXISTS `wf_process_definition`;
CREATE TABLE `wf_process_definition` (
    `id`                  BIGINT          NOT NULL AUTO_INCREMENT COMMENT '主键ID',
    `process_key`         VARCHAR(64)     NOT NULL                COMMENT '流程标识键(如 leave-apply)',
    `process_name`        VARCHAR(100)    NOT NULL                COMMENT '流程名称',
    `version`             INT             NOT NULL DEFAULT 1      COMMENT '版本号(自增)',
    `definition_json`     LONGTEXT        NOT NULL                COMMENT '流程定义JSON(含所有节点和连线信息)',
    `svg_xml`             LONGTEXT        DEFAULT NULL            COMMENT '流程图SVG XML(可视化设计器生成)',
    `description`         VARCHAR(500)    DEFAULT NULL            COMMENT '流程描述',
    `category`            VARCHAR(50)     DEFAULT NULL            COMMENT '分类(如 请假/报销/采购)',
    `status`              TINYINT         NOT NULL DEFAULT 1      COMMENT '状态: 0挂起 1激活',
    `deploy_time`         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '部署时间',
    `deploy_by`           BIGINT          DEFAULT NULL            COMMENT '部署人',
    `suspension_state`    TINYINT         NOT NULL DEFAULT 1      COMMENT '挂起状态: 1激活 2挂起',
    `form_config`         JSON            DEFAULT NULL            COMMENT '表单配置(JSON格式,动态表单定义)',
    `create_time`         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time`         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `deleted`             TINYINT         NOT NULL DEFAULT 0      COMMENT '逻辑删除: 0未删 1已删除',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_key_version` (`process_key`, `version`),
    KEY `idx_category` (`category`),
    KEY `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='流程定义表';

-- -----------------------------------------------------------
-- 7. wf_process_instance 流程实例表
-- -----------------------------------------------------------
DROP TABLE IF EXISTS `wf_process_instance`;
CREATE TABLE `wf_process_instance` (
    `id`                  BIGINT          NOT NULL AUTO_INCREMENT COMMENT '主键ID',
    `instance_no`         VARCHAR(32)     NOT NULL                COMMENT '实例编号(业务编号,如 PI20260610001)',
    `process_def_id`      BIGINT          NOT NULL                COMMENT '流程定义ID',
    `process_key`         VARCHAR(64)     NOT NULL                COMMENT '流程标识键',
    `process_name`        VARCHAR(100)    NOT NULL                COMMENT '流程名称(快照)',
    `start_user_id`       BIGINT          NOT NULL                COMMENT '发起人ID',
    `start_user_name`     VARCHAR(50)     DEFAULT NULL            COMMENT '发起人姓名(冗余,避免联查)',
    `current_node_id`     VARCHAR(64)     DEFAULT NULL            COMMENT '当前节点ID',
    `current_node_name`   VARCHAR(100)    DEFAULT NULL            COMMENT '当前节点名称',
    `business_key`        VARCHAR(64)     DEFAULT NULL            COMMENT '业务键(关联外部业务数据)',
    `business_type`       VARCHAR(50)     DEFAULT NULL            COMMENT '业务类型(如 leave_order)',
    `variables`           JSON            DEFAULT NULL            COMMENT '流程变量(JSON,如 {days:3, reason:"病假"})',
    `status`              VARCHAR(20)     NOT NULL DEFAULT 'RUNNING' COMMENT '运行状态: RUNNING/COMPLETED/CANCELLED/SUSPENDED',
    `result`              VARCHAR(20)     DEFAULT NULL            COMMENT '最终结果: APPROVED/REJECTED/TIMEOUT/CANCELLED',
    `start_time`          DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '开始时间',
    `end_time`            DATETIME        DEFAULT NULL            COMMENT '结束时间',
    `duration_ms`         BIGINT          DEFAULT NULL            COMMENT '耗时(毫秒)',
    `delete_reason`       VARCHAR(255)    DEFAULT NULL            COMMENT '取消/删除原因',
    `create_time`         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time`         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_instance_no` (`instance_no`),
    KEY `idx_def_id` (`process_def_id`),
    KEY `idx_start_user` (`start_user_id`),
    KEY `idx_status` (`status`),
    KEY `idx_business_key` (`business_key`, `business_type`),
    KEY `idx_start_time` (`start_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='流程实例表';

-- -----------------------------------------------------------
-- 8. wf_task_instance 任务实例表（待办/已办）
-- -----------------------------------------------------------
DROP TABLE IF EXISTS `wf_task_instance`;
CREATE TABLE `wf_task_instance` (
    `id`                  BIGINT          NOT NULL AUTO_INCREMENT COMMENT '主键ID',
    `task_no`             VARCHAR(32)     NOT NULL                COMMENT '任务编号',
    `instance_id`         BIGINT          NOT NULL                COMMENT '流程实例ID',
    `node_id`             VARCHAR(64)     NOT NULL                COMMENT '节点ID(对应流程定义中的nodeId)',
    `node_name`           VARCHAR(100)    NOT NULL                COMMENT '节点名称',
    `node_type`           VARCHAR(30)     NOT NULL                COMMENT '节点类型: UserTask/ServiceTask/TimerTask',
    `assignee`            BIGINT          DEFAULT NULL            COMMENT '办理人ID(单个审批人)',
    `assignee_name`       VARCHAR(50)     DEFAULT NULL            COMMENT '办理人姓名(冗余)',
    `candidate_users`     VARCHAR(500)    DEFAULT NULL            COMMENT '候选人工ID列表(逗号分隔,用于会签)',
    `candidate_groups`    VARCHAR(500)    DEFAULT NULL            COMMENT '候选人组(角色编码)',
    `priority`            INT             DEFAULT 50               COMMENT '优先级: 0-100,值越大优先级越高',
    `status`              VARCHAR(20)     NOT NULL DEFAULT 'PENDING' COMMENT '任务状态: PENDING/COMPLETED/DELEGATED/RETURNED/CANCELLED/TIMEOUT',
    `action`              VARCHAR(20)     DEFAULT NULL            COMMENT '操作动作: APPROVE/REJECT/RETURN/DELEGATE/TRANSFER',
    `comment`             TEXT            DEFAULT NULL            COMMENT '审批意见',
    `form_data`           JSON            DEFAULT NULL            COMMENT '表单数据(JSON,用户填写的内容)',
    `claim_time`          DATETIME        DEFAULT NULL            COMMENT '认领时间',
    `complete_time`       DATETIME        DEFAULT NULL            COMMENT '完成时间',
    `due_date`            DATETIME        DEFAULT NULL            COMMENT '到期时间(超时提醒用)',
    `execution_strategy`  VARCHAR(20)     DEFAULT 'SYNC'          COMMENT '执行策略(创新点一): SYNC/ASYNC_THREAD/ASYNC_QUEUE/CACHED_EVAL',
    `duration_ms`         BIGINT          DEFAULT NULL            COMMENT '耗时(毫秒)',
    `process_variables`   JSON            DEFAULT NULL            COMMENT '任务级别流程变量(快照)',
    `create_time`         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time`         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_task_no` (`task_no`),
    KEY `idx_instance_id` (`instance_id`),
    KEY `idx_assignee` (`assignee`, `status`),
    KEY `idx_status` (`status`),
    KEY `idx_node_id` (`node_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='任务实例表';

-- -----------------------------------------------------------
-- 9. wf_execution_pointer 执行指针表（引擎内部使用，记录流程推进位置）
-- -----------------------------------------------------------
DROP TABLE IF EXISTS `wf_execution_pointer`;
CREATE TABLE `wf_execution_pointer` (
    `id`                  BIGINT          NOT NULL AUTO_INCREMENT COMMENT '主键ID',
    `instance_id`         BIGINT          NOT NULL                COMMENT '流程实例ID',
    `pointer_name`        VARCHAR(64)     NOT NULL                COMMENT '指针名称',
    `current_node_id`     VARCHAR(64)     NOT NULL                COMMENT '当前位置节点ID',
    `parent_pointer_id`   BIGINT          DEFAULT NULL            COMMENT '父指针ID(子流程场景)',
    `is_active`           TINYINT         NOT NULL DEFAULT 1      COMMENT '是否活跃: 0否 1是',
    `is_scope`            TINYINT         NOT NULL DEFAULT 0      COMMENT '是否作用域(子流程/并行网关)',
    `stack_trace`         TEXT            DEFAULT NULL            COMMENT '调用栈轨迹(JSON数组,用于异常恢复)',
    `variable_snapshot`   JSON            DEFAULT NULL            COMMENT '变量快照',
    `create_time`         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time`         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`id`),
    KEY `idx_instance_id` (`instance_id`, `is_active`),
    KEY `idx_current_node` (`current_node_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='执行指针表';

-- -----------------------------------------------------------
-- 10. wf_history_activity 历史活动记录表（审计追踪，不可修改）
-- -----------------------------------------------------------
DROP TABLE IF EXISTS `wf_history_activity`;
CREATE TABLE `wf_history_activity` (
    `id`                  BIGINT          NOT NULL AUTO_INCREMENT COMMENT '主键ID',
    `instance_id`         BIGINT          NOT NULL                COMMENT '流程实例ID',
    `task_id`             BIGINT          DEFAULT NULL            COMMENT '关联任务ID',
    `node_id`             VARCHAR(64)     NOT NULL                COMMENT '节点ID',
    `node_name`           VARCHAR(100)    DEFAULT NULL            COMMENT '节点名称',
    `node_type`           VARCHAR(30)     NOT NULL                COMMENT '节点类型',
    `executor_id`         BIGINT          DEFAULT NULL            COMMENT '执行人ID',
    `executor_name`       VARCHAR(50)     DEFAULT NULL            COMMENT '执行人姓名',
    `action`              VARCHAR(20)     DEFAULT NULL            COMMENT '执行动作: START/COMPLETE/APPROVE/REJECT/RETURN/TRANSFER/TIMEOUT',
    `comment`             TEXT            DEFAULT NULL            COMMENT '处理意见',
    `start_time`          DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '进入此节点的时间',
    `end_time`            DATETIME        DEFAULT NULL            COMMENT '离开此节点的时间',
    `duration_ms`         BIGINT          DEFAULT NULL            COMMENT '在此节点停留时长(毫秒)',
    `variables_before`    JSON            DEFAULT NULL            COMMENT '进入时的流程变量(快照)',
    `variables_after`     JSON            DEFAULT NULL            COMMENT '离开时的流程变量(快照)',
    `create_time`         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间(即写入时间,不再允许update)',
    PRIMARY KEY (`id`),
    KEY `idx_instance_id` (`instance_id`),
    KEY `idx_executor` (`executor_id`),
    KEY `idx_start_time` (`start_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='历史活动记录表';


-- ============================================================================
-- 第三部分：任务调度域（2张表）— 分布式调度中心 + 执行器通信
-- ============================================================================

-- -----------------------------------------------------------
-- 11. schedule_job_info 任务信息表
-- -----------------------------------------------------------
DROP TABLE IF EXISTS `schedule_job_info`;
CREATE TABLE `schedule_job_info` (
    `id`                  BIGINT          NOT NULL AUTO_INCREMENT COMMENT '主键ID',
    `job_group`           VARCHAR(50)     NOT NULL DEFAULT 'DEFAULT' COMMENT '执行器分组',
    `job_name`            VARCHAR(100)    NOT NULL                COMMENT '任务名称',
    `job_desc`            VARCHAR(255)    DEFAULT NULL            COMMENT '任务描述',
    `handler_name`        VARCHAR(100)    NOT NULL                COMMENT '执行器中注册的Handler名称',
    `handler_params`      VARCHAR(500)    DEFAULT NULL            COMMENT '执行参数(JSON字符串)',
    `cron_expression`     VARCHAR(128)    DEFAULT NULL            COMMENT 'Cron表达式',
    `route_strategy`      VARCHAR(30)     NOT NULL DEFAULT 'ROUND' COMMENT '路由策略: FIRST/LAST/ROUND/RANDOM/CONSISTENT_HASH/LFU/LRU/FAILOVER/BUSYOVER/SHARDING_BROADCAST',
    `sharding_total`      INT             DEFAULT 1               COMMENT '分片总数(SHARDING_BROADCAST模式有效)',
    `misfire_strategy`    VARCHAR(20)     NOT NULL DEFAULT 'DO_NOTHING' COMMENT '错失处理: DO_NOTHING/FIRE_ONCE',
    `block_strategy`      VARCHAR(20)     NOT NULL DEFAULT 'SERIAL_EXECUTION' COMMENT '阻塞策略: SERIAL_EXECUTION/DISCARD_LATER/COVER_EARLY',
    `executor_timeout`    INT             DEFAULT 0               COMMENT '超时时间(秒), 0表示不限',
    `executor_fail_retry` INT             DEFAULT 0               COMMENT '失败重试次数',
    `glue_type`           VARCHAR(20)     NOT NULL DEFAULT 'BEAN' COMMENT 'GLUE类型: BEAN/GLUE_SHELL/GLUE_PYTHON/GLUE_GROOVY',
    `glue_source`         LONGTEXT        DEFAULT NULL            COMMENT 'GLUE脚本源码',
    `glue_remark`         VARCHAR(255)    DEFAULT NULL            COMMENT 'GLUE备注',
    `glue_updatetime`     DATETIME        DEFAULT NULL            COMMENT 'GLUE更新时间',
    `child_job_ids`       VARCHAR(200)    DEFAULT NULL            COMMENT '子任务ID(逗号分隔)',
    `schedule_status`     TINYINT         NOT NULL DEFAULT 0      COMMENT '调度状态: 0停止 1运行中',
    `schedule_type`       TINYINT         NOT NULL DEFAULT 0      COMMENT '调度类型: 0 NONE/1 CRON/2 FIX_RATE/3 MANUAL',
    `schedule_conf`       VARCHAR(128)    DEFAULT NULL            COMMENT '调度配置(Cron表达式或固定速率)',
    `trigger_last_time`   BIGINT          DEFAULT 0               COMMENT '上次触发时间(时间戳ms)',
    `trigger_next_time`   BIGINT          DEFAULT 0               COMMENT '下次触发时间(时间戳ms)',
    `author`              VARCHAR(50)     DEFAULT NULL            COMMENT '负责人',
    `alarm_email`         VARCHAR(255)    DEFAULT NULL            COMMENT '告警邮件(逗号分隔)',
    `execute_mode`        VARCHAR(20)     DEFAULT 'STANDALONE'    COMMENT '执行模式: STANDALONE/CLUSTER',
    `create_by`           BIGINT          DEFAULT NULL            COMMENT '创建人',
    `create_time`         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_by`           BIGINT          DEFAULT NULL            COMMENT '更新人',
    `update_time`         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `deleted`             TINYINT         NOT NULL DEFAULT 0      COMMENT '逻辑删除: 0未删 1已删除',
    PRIMARY KEY (`id`),
    KEY `idx_job_group_name` (`job_group`, `job_name`),
    KEY `idx_schedule_status` (`schedule_status`),
    KEY `idx_trigger_next` (`trigger_next_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='任务调度信息表';

-- -----------------------------------------------------------
-- 12. schedule_job_log 调度日志表
-- -----------------------------------------------------------
DROP TABLE IF EXISTS `schedule_job_log`;
CREATE TABLE `schedule_job_log` (
    `id`                  BIGINT          NOT NULL AUTO_INCREMENT COMMENT '主键ID',
    `job_id`              BIGINT          NOT NULL                COMMENT '任务ID(schedule_job_info.id)',
    `job_group`           VARCHAR(50)     NOT NULL                COMMENT '执行器分组',
    `job_name`            VARCHAR(100)    NOT NULL                COMMENT '任务名称',
    `executor_address`    VARCHAR(255)    DEFAULT NULL            COMMENT '执行器地址(IP:Port)',
    `executor_handler`    VARCHAR(100)    DEFAULT NULL            COMMENT '执行器Handler',
    `executor_param`      VARCHAR(500)    DEFAULT NULL            COMMENT '执行参数',
    `executor_sharding_param` VARCHAR(100)DEFAULT NULL            COMMENT '分片参数(如 0/3)',
    `trigger_time`        DATETIME        NOT NULL                COMMENT '调度时间',
    `trigger_code`        INT             NOT NULL                COMMENT '调度结果: 200成功 500失败 502超时 503失败重试',
    `trigger_msg`         TEXT            DEFAULT NULL            COMMENT '调度信息(错误堆栈等)',
    `handle_time`         DATETIME        DEFAULT NULL            COMMENT '执行完成时间',
    `handle_code`         INT             DEFAULT NULL            COMMENT '执行结果: 200成功 500失败 502超时',
    `handle_msg`          TEXT            DEFAULT NULL            COMMENT '执行信息(返回结果/异常堆栈)',
    `handle_duration_ms`  INT             DEFAULT NULL            COMMENT '执行耗时(毫秒)',
    `alarm_status`        TINYINT         DEFAULT 0               COMMENT '告警状态: 0默认 -1告警成功 -2告警失败 1无需告警',
    `create_time`         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (`id`),
    KEY `idx_job_id` (`job_id`),
    KEY `idx_trigger_time` (`trigger_time`),
    KEY `idx_handle_code` (`handle_code`),
    KEY `idx_executor_address` (`executor_address`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='任务调度日志表';


-- ============================================================================
-- 第四部分：消息通知域（2张表）— 站内信 / 邮件 / 短信 / Webhook
-- ============================================================================

-- -----------------------------------------------------------
-- 13. msg_template 消息模板表
-- -----------------------------------------------------------
DROP TABLE IF EXISTS `msg_template`;
CREATE TABLE `msg_template` (
    `id`                  BIGINT          NOT NULL AUTO_INCREMENT COMMENT '主键ID',
    `template_code`       VARCHAR(50)     NOT NULL                COMMENT '模板编码(如 TASK_APPROVAL_NOTIFY)',
    `template_name`       VARCHAR(100)    NOT NULL                COMMENT '模板名称',
    `template_title`      VARCHAR(200)    NOT NULL                COMMENT '消息标题(支持变量 ${var})',
    `template_content`    TEXT            NOT NULL                COMMENT '消息内容(支持变量 ${var}, 支持HTML)',
    `msg_type`            VARCHAR(20)     NOT NULL                COMMENT '消息类型: SITE_MESSAGE/EMAIL/SMS/WEBHOOK',
    `channel`             VARCHAR(20)     DEFAULT NULL            COMMENT '发送渠道: DINGTALK/WECOM/ALIYUN_SMS/TWILIO',
    `status`              TINYINT         NOT NULL DEFAULT 1      COMMENT '状态: 0禁用 1启用',
    `remark`              VARCHAR(500)    DEFAULT NULL            COMMENT '备注',
    `create_by`           BIGINT          DEFAULT NULL            COMMENT '创建人',
    `create_time`         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_by`           BIGINT          DEFAULT NULL            COMMENT '更新人',
    `update_time`         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `deleted`             TINYINT         NOT NULL DEFAULT 0      COMMENT '逻辑删除: 0未删 1已删除',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_template_code` (`template_code`),
    KEY `idx_msg_type` (`msg_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='消息模板表';

-- -----------------------------------------------------------
-- 14. msg_record 消息发送记录表
-- -----------------------------------------------------------
DROP TABLE IF EXISTS `msg_record`;
CREATE TABLE `msg_record` (
    `id`                  BIGINT          NOT NULL AUTO_INCREMENT COMMENT '主键ID',
    `template_id`         BIGINT          DEFAULT NULL            COMMENT '模板ID',
    `template_code`       VARCHAR(50)     DEFAULT NULL            COMMENT '模板编码(冗余)',
    `msg_type`            VARCHAR(20)     NOT NULL                COMMENT '消息类型',
    `sender_id`           BIGINT          DEFAULT NULL            COMMENT '发送人ID(系统发送则为NULL)',
    `receiver_id`         BIGINT          NOT NULL                COMMENT '接收人ID',
    `receiver_name`       VARCHAR(50)     DEFAULT NULL            COMMENT '接收人姓名(冗余)',
    `title`               VARCHAR(200)    NOT NULL                COMMENT '消息标题(渲染后)',
    `content`             TEXT            DEFAULT NULL            COMMENT '消息内容(渲染后)',
    `biz_type`            VARCHAR(30)     DEFAULT NULL            COMMENT '业务类型: WORKFLOW_TASK/SYSTEM_ALERT/SCHEDULE_ALARM',
    `biz_id`              BIGINT          DEFAULT NULL            COMMENT '业务关联ID(如任务实例ID)',
    `send_status`         TINYINT         NOT NULL DEFAULT 0      COMMENT '发送状态: 0待发送 1发送中 2发送成功 3发送失败',
    `send_time`           DATETIME        DEFAULT NULL            COMMENT '实际发送时间',
    `error_msg`           TEXT            DEFAULT NULL            COMMENT '错误信息(失败时记录)',
    `read_status`         TINYINT         NOT NULL DEFAULT 0      COMMENT '阅读状态(仅站内信有效): 0未读 1已读',
    `read_time`           DATETIME        DEFAULT NULL            COMMENT '阅读时间',
    `retry_count`         INT             NOT NULL DEFAULT 0      COMMENT '重试次数',
    `next_retry_time`     DATETIME        DEFAULT NULL            COMMENT '下次重试时间',
    `create_time`         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time`         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`id`),
    KEY `idx_receiver_id` (`receiver_id`, `read_status`),
    KEY `idx_send_status` (`send_status`),
    KEY `idx_biz` (`biz_type`, `biz_id`),
    KEY `idx_create_time` (`create_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='消息发送记录表';


-- ============================================================================
-- 第五部分：系统管理域（2张表）— 操作日志 + 字典管理
-- ============================================================================

-- -----------------------------------------------------------
-- 15. sys_oper_log 操作日志表（安全审计）
-- -----------------------------------------------------------
DROP TABLE IF EXISTS `sys_oper_log`;
CREATE TABLE `sys_oper_log` (
    `id`                  BIGINT          NOT NULL AUTO_INCREMENT COMMENT '主键ID',
    `module`              VARCHAR(50)     DEFAULT NULL            COMMENT '模块标题',
    `business_type`       TINYINT         DEFAULT 0               COMMENT '业务类型(0其它 1新增 2修改 3删除 4授权 5导出 6导入 7强退 8生成代码 9清空数据)',
    `method`              VARCHAR(200)    DEFAULT NULL            COMMENT '方法名称',
    `request_method`      VARCHAR(10)     DEFAULT NULL            COMMENT '请求方式(GET/POST/PUT/DELETE)',
    `operator_type`       TINYINT         DEFAULT 0               COMMENT '操作类别(0后端 1手机 2其他)',
    `oper_name`           VARCHAR(50)     DEFAULT NULL            COMMENT '操作人员',
    `oper_url`            VARCHAR(255)    DEFAULT NULL            COMMENT '请求URL',
    `oper_ip`             VARCHAR(128)    DEFAULT NULL            COMMENT '主机地址',
    `oper_location`       VARCHAR(255)    DEFAULT NULL            COMMENT '操作地点',
    `oper_param`          LONGTEXT        DEFAULT NULL            COMMENT '请求参数(JSON格式)',
    `json_result`         LONGTEXT        DEFAULT NULL            COMMENT '返回参数(JSON格式)',
    `status`              TINYINT         DEFAULT 0               COMMENT '操作状态(0正常 1异常)',
    `error_msg`           TEXT            DEFAULT NULL            COMMENT '错误消息',
    `oper_time`           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '操作时间',
    `cost_time_ms`        BIGINT          DEFAULT 0               COMMENT '消耗时间(毫秒)',
    PRIMARY KEY (`id`),
    KEY `idx_oper_time` (`oper_time`),
    KEY `idx_oper_name` (`oper_name`),
    KEY `idx_status` (`status`),
    KEY `idx_business_type` (`business_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='操作日志表';

-- -----------------------------------------------------------
-- 16. sys_dict_type 字典类型表 + sys_dict_data 字典数据表
-- -----------------------------------------------------------
DROP TABLE IF EXISTS `sys_dict_type`;
CREATE TABLE `sys_dict_type` (
    `id`              BIGINT          NOT NULL AUTO_INCREMENT COMMENT '主键ID',
    `dict_name`       VARCHAR(100)    NOT NULL                COMMENT '字典名称',
    `dict_type`       VARCHAR(100)    NOT NULL                COMMENT '字典类型(唯一标识)',
    `status`          TINYINT         NOT NULL DEFAULT 1      COMMENT '状态: 0停用 1正常',
    `remark`          VARCHAR(500)    DEFAULT NULL            COMMENT '备注',
    `create_by`       BIGINT          DEFAULT NULL            COMMENT '创建人',
    `create_time`     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_by`       BIGINT          DEFAULT NULL            COMMENT '更新人',
    `update_time`     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `deleted`         TINYINT         NOT NULL DEFAULT 0      COMMENT '逻辑删除: 0未删 1已删除',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_dict_type` (`dict_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='字典类型表';

DROP TABLE IF EXISTS `sys_dict_data`;
CREATE TABLE `sys_dict_data` (
    `id`              BIGINT          NOT NULL AUTO_INCREMENT COMMENT '主键ID',
    `dict_type`       VARCHAR(100)    NOT NULL                COMMENT '字典类型',
    `dict_label`      VARCHAR(100)    NOT NULL                COMMENT '字典标签',
    `dict_value`      VARCHAR(100)    NOT NULL                COMMENT '字典键值',
    `dict_sort`       INT             DEFAULT 0               COMMENT '排序',
    `css_class`       VARCHAR(100)    DEFAULT NULL            COMMENT '样式属性(如 color:red)',
    `list_class`      VARCHAR(100)    DEFAULT NULL            COMMENT '表格回显样式',
    `is_default`      TINYINT         NOT NULL DEFAULT 0      COMMENT '是否默认: 0否 1是',
    `status`          TINYINT         NOT NULL DEFAULT 1      COMMENT '状态: 0停用 1正常',
    `remark`          VARCHAR(500)    DEFAULT NULL            COMMENT '备注',
    `create_by`       BIGINT          DEFAULT NULL            COMMENT '创建人',
    `create_time`     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_by`       BIGINT          DEFAULT NULL            COMMENT '更新人',
    `update_time`     DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`id`),
    KEY `idx_dict_type` (`dict_type`),
    KEY `idx_dict_value` (`dict_type`, `dict_value`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='字典数据表';


-- ============================================================================
-- 第六部分：文件存储域（1张表）— MinIO 对象存储元数据
-- ============================================================================

-- -----------------------------------------------------------
-- 17. file_info 文件信息表
-- -----------------------------------------------------------
DROP TABLE IF EXISTS `file_info`;
CREATE TABLE `file_info` (
    `id`                  BIGINT          NOT NULL AUTO_INCREMENT COMMENT '主键ID',
    `file_name`           VARCHAR(255)    NOT NULL                COMMENT '原始文件名',
    `file_size`           BIGINT          NOT NULL                COMMENT '文件大小(字节)',
    `file_ext`            VARCHAR(20)     DEFAULT NULL            COMMENT '文件扩展名(如 pdf/jpg/docx)',
    `file_md5`            VARCHAR(32)     NOT NULL                COMMENT 'MD5校验值(用于秒传判重)',
    `content_type`        VARCHAR(100)    DEFAULT NULL            CONTENT_TYPE(MIME类型),
    `storage_path`        VARCHAR(500)    NOT NULL                COMMENT 'MinIO存储路径(bucket/key)',
    `bucket_name`         VARCHAR(100)    NOT NULL                COMMENT 'MinIO Bucket名称',
    `upload_id`           VARCHAR(64)     DEFAULT NULL            COMMENT '分片上传ID(断点续传用)',
    `chunk_index`         INT             DEFAULT NULL            COMMENT '当前分片索引',
    `chunk_total`         INT             DEFAULT NULL            COMMENT '总分片数',
    `chunk_size`          BIGINT          DEFAULT NULL            COMMENT '分片大小(字节)',
    `uploader_id`         BIGINT          DEFAULT NULL            COMMENT '上传人ID',
    `biz_type`            VARCHAR(30)     DEFAULT NULL            COMMENT '业务类型: WORKFLOW_ATTACH/AVATAR/TEMP/EXPORT',
    `biz_id`              BIGINT          DEFAULT NULL            COMMENT '业务关联ID',
    `download_url`        VARCHAR(500)    DEFAULT NULL            COMMENT '预签名下载URL(临时)',
    `preview_url`         VARCHAR(500)    DEFAULT NULL            COMMENT '在线预览URL',
    `thumbnail_url`       VARCHAR(500)    DEFAULT NULL            COMMENT '缩略图URL(图片/视频专用)',
    `is_chunked`          TINYINT         NOT NULL DEFAULT 0      COMMENT '是否分片上传: 0否 1是',
    `merge_status`        TINYINT         DEFAULT NULL            COMMENT '合并状态: NULL未开始 0进行中 1已完成 2失败',
    `access_permission`   TINYINT         NOT NULL DEFAULT 0      COMMENT '访问权限: 0公开 1登录可访问 2指定人可见',
    `expire_time`         DATETIME        DEFAULT NULL            COMMENT '过期时间(临时文件用)',
    `status`              TINYINT         NOT NULL DEFAULT 1      COMMENT '状态: 0已删除 1正常',
    `create_time`         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time`         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    `deleted`             TINYINT         NOT NULL DEFAULT 0      COMMENT '逻辑删除: 0未删 1已删除',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uk_file_md5` (`file_md5`, `file_size`) COMMENT 'MD5+大小联合唯一(秒传判重)',
    KEY `idx_bucket` (`bucket_name`),
    KEY `idx_uploader` (`uploader_id`),
    KEY `idx_biz` (`biz_type`, `biz_id`),
    KEY `idx_upload_time` (`create_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='文件信息表';


-- ============================================================================
-- 第七部分：初始数据 — 预置管理员账户 + 基础字典数据
-- ============================================================================

-- 默认管理员: admin / admin123 (BCrypt)
INSERT INTO `sys_user` (`username`, `password`, `nickname`, `email`, `phone`, `status`, `create_by`) VALUES
('admin', '$2a$10$7JB720yubVSZvUI0rEqK/.VqGOZTH.ulu33dHOiBE8ByOhJIrdAu2', '超级管理员', 'admin@flowpulse.com', '13800138000', 1, 0);

-- 默认角色
INSERT INTO `sys_role` (`role_name`, `role_code`, `parent_id`, `sort_order`, `data_scope`) VALUES
('超级管理员', 'ROLE_SUPER_ADMIN', 0, 1, '1'),
('普通用户',   'ROLE_USER',        0, 2, '5');

-- 管理员分配角色
INSERT INTO `sys_user_role` (`user_id`, `role_id`) VALUES (1, 1);

-- 基础菜单权限数据
INSERT INTO `sys_permission` (`permission_name`, `permission_code`, `parent_id`, `menu_type`, `path`, `icon`, `sort_order`) VALUES
('系统管理',       'system',           0, 'M', '/system',      'setting',   1),
('用户管理',       'system:user',      1, 'C', 'user',         'user',      1),
('角色管理',       'system:role',      1, 'C', 'role',         'peoples',   2),
('菜单管理',       'system:menu',      1, 'C', 'menu',         'tree-table',3),
('流程管理',       'workflow',         0, 'M', '/workflow',    'edit',      2),
('流程定义',       'workflow:def',     5, 'C', 'definition',   'document',  1),
('我的流程',       'workflow:mine',    5, 'C', 'my-processes', 'guide',     2),
('我的任务',       'workflow:task',    5, 'C', 'tasks',        'checkbox',  3),
('任务调度',       'scheduler',        0, 'M', '/scheduler',   'time',      3),
('任务管理',       'scheduler:job',    9, 'C', 'job',          'list',      1),
('调度日志',       'scheduler:log',    9, 'C', 'log',          'log',       2);

-- 角色分配菜单权限(超级管理员拥有所有权限)
INSERT INTO `sys_role_permission` (`role_id`, `permission_id`) SELECT 1, id FROM `sys_permission`;

-- 字典类型初始数据
INSERT INTO `sys_dict_type` (`dict_name`, `dict_type`, `remark`) VALUES
('流程实例状态', 'wf_instance_status', '工作流实例运行状态'),
('任务状态',       'wf_task_status',    '工作流任务状态'),
('操作动作',       'wf_action',         '流程操作动作'),
('节点类型',       'wf_node_type',      '工作流节点类型'),
('消息类型',       'msg_type',          '消息通知类型'),
('消息发送状态',   'msg_send_status',   '消息发送状态'),
('性别',           'sys_gender',        '用户性别'),
('通用开关状态',   'sys_common_switch', '通用是否开关');

-- 字典数据初始数据
INSERT INTO `sys_dict_data` (`dict_type`, `dict_label`, `dict_value`, `dict_sort`, `css_class`, `is_default`, `status`) VALUES
('wf_instance_status', '运行中',   'RUNNING',    1, '', 0, 1),
('wf_instance_status', '已完成',   'COMPLETED',  2, '', 0, 1),
('wf_instance_status', '已取消',   'CANCELLED',  3, '', 0, 1),
('wf_instance_status', '已挂起',   'SUSPENDED',  4, '', 0, 1),
('wf_task_status',     '待处理',   'PENDING',    1, '', 0, 1),
('wf_task_status',     '已完成',   'COMPLETED',  2, '', 0, 1),
('wf_task_status',     '已转办',   'DELEGATED',  3, '', 0, 1),
('wf_task_status',     '已驳回',   'RETURNED',   4, '', 0, 1),
('wf_task_status',     '已取消',   'CANCELLED',  5, '', 0, 1),
('wf_task_status',     '已超时',   'TIMEOUT',    6, '', 0, 1),
('wf_action',          '同意',     'APPROVE',    1, '', 0, 1),
('wf_action',          '拒绝',     'REJECT',     2, '', 0, 1),
('wf_action',          '驳回',     'RETURN',     3, '', 0, 1),
('wf_action',          '转办',     'TRANSFER',   4, '', 0, 1),
('wf_action',          '委托',     'DELEGATE',   5, '', 0, 1),
('wf_node_type',       '开始事件', 'StartEvent',      1, '', 0, 1),
('wf_node_type',       '结束事件', 'EndEvent',        2, '', 0, 1),
('wf_node_type',       '用户任务', 'UserTask',        3, '', 0, 1),
('wf_node_type',       '服务任务', 'ServiceTask',     4, '', 0, 1),
('wf_node_type',       '定时任务', 'TimerTask',       5, '', 0, 1),
('wf_node_type',       '排他网关', 'ExclusiveGateway',6, '', 0, 1),
('wf_node_type',       '并行网关', 'ParallelGateway',7, '', 0, 1),
('msg_type',           '站内信',   'SITE_MESSAGE', 1, '', 0, 1),
('msg_type',           '邮件',     'EMAIL',         2, '', 0, 1),
('msg_type',           '短信',     'SMS',           3, '', 0, 1),
('msg_type',           'Webhook',  'WEBHOOK',       4, '', 0, 1),
('msg_send_status',    '待发送',   '0',             1, '', 0, 1),
('msg_send_status',    '发送中',   '1',             2, '', 0, 1),
('msg_send_status',    '发送成功', '2',             3, '', 0, 1),
('msg_send_status',    '发送失败', '3',             4, '', 0, 1),
('sys_gender',         '未知',     '0',             1, '', 1, 1),
('sys_gender',         '男',       '1',             2, '', 0, 1),
('sys_gender',         '女',       '2',             3, '', 0, 1),
('sys_common_switch',  '关闭',     '0',             1, '', 1, 1),
('sys_common_switch',  '打开',     '1',             2, '', 0, 1);


-- ============================================================================
-- 第八部分：Redis Key 设计规范 + 索引优化说明
-- ============================================================================

/*
 * ==================== Redis Key 设计规范 ====================
 *
 * [认证模块]
 *   flowpulse:token:{jti}                          -> JWT Token 黑名单 (TTL = token剩余有效期)
 *   flowpulse:user:online:{userId}                 -> 在线用户 Session (心跳续期, TTL=30min)
 *   flowpulse:captcha:{sessionId}                  -> 图形验证码 (TTL=5min)
 *   flowpulse:login:fail:{username}                -> 登录失败计数 (TTL=15min, 超5次锁定)
 *
 * [工作流模块]
 *   flowpulse:wf:def:{defId}:lock                  -> 流程定义版本部署锁
 *   flowpulse:wf:inst:{instId}:lock                 -> 流程实例并发推进锁
 *   flowpulse:wf:task:assignee:{userId}:pending     -> 用户待办任务计数 (实时更新)
 *   flowpulse:wf:node:{nodeId}:condition:cache      -> 排他网关条件缓存 (创新点一)
 *
 * [分布式事务] (Seata AT模式自动管理)
 *   flowpulse:tx:global:{xid}                      -> 全局事务锁 (Seata框架维护)
 *   flowpulse:tx:branch:{branchId}                 -> 分支事务锁
 *
 * [API网关]
 *   flowpulse:gateway:rate:{api}:{userId}          -> 令牌桶限流计数
 *   flowpulse:gateway:blacklist:{ip}               -> IP黑名单
 *   flowpulse:gateway:route:{routeId}               -> 动态路由配置缓存
 *
 * [任务调度]
 *   flowpulse:scheduler:job:{jobId}:running        -> 任务运行互斥锁
 *   flowpulse:scheduler:registry:{executor}         -> 执行器注册信息 (心跳续期)
 *   flowpulse:scheduler:counter:{jobId}:shard:{index} -> 分片广播计数器
 *
 * [文件服务]
 *   flowpulse:file:md5:{md5}                       -> MD5秒传判重 (TTL=24h)
 *   flowpulse:file:chunk:{uploadId}                -> 分片上传进度 (TTL=24h)
 *
 * ==================== 关键索引说明 ====================
 * 所有表的索引设计遵循以下原则:
 * 1. 主键统一使用 BIGINT 自增, 避免UUID随机写入性能问题
 * 2. 高频查询条件建立复合索引 (如 assignee+status)
 * 3. 外键关联字段建普通索引, 避免 JOIN 全表扫描
 * 4. 时间字段建单独索引, 支持范围查询和时间线归档
 * 5. 唯一约束用于业务去重 (如 username, role_code, task_no)
 * 6. JSON字段(MySQL 8.0+) 用于灵活的流程变量/表单数据存储
 */


-- ============================================================================
-- 完成！
-- ============================================================================
-- 统计:
--   认证授权域:  5 张表 (sys_user, sys_role, sys_permission, sys_user_role, sys_role_permission)
--   工作流引擎域: 5 张表 (wf_process_definition, wf_process_instance, wf_task_instance,
--                     wf_execution_pointer, wf_history_activity)
--   任务调度域:   2 张表 (schedule_job_info, schedule_job_log)
--   消息通知域:   2 张表 (msg_template, msg_record)
--   系统管理域:   2 张表 (sys_oper_log, sys_dict_type + sys_dict_data)
--   文件存储域:   1 张表 (file_info)
--   ──────────────────────────────────────────────
--   合计:         17 张表 + 初始数据(管理员/角色/菜单/字典)
-- ============================================================================
